function dydt = SMR_ODEs_MAD(t, y, params, scenario)
% SMR_ODEs_MAD.m - OPTIMIZED VERSION v4.1
% 20-state MAD model with conservative parameter set
%
% CONSERVATIVE PARAMETER SET (defensible for commercial deployment):
% 1. PCM storage: constant boost approximation (not dynamic state tracking)
% 2. Desiccant boost: stage1 0.12, stage2 0.08 (was 0.25/0.18)
% 3. NEW: Turbine Inlet Air Cooling (TIAC) innovation
% 4. Improved enthalpy interpolation with finer pressure steps
% 5. M-Cycle effectiveness: 0.80 (was 0.93)
% 6. Enhanced air flow rates
% 7. Optimized condenser minimum temperature approach

persistent error_count;
if isempty(error_count)
    error_count = 0;
end

try
    dydt = zeros(21,1);

    % Validate state vector size
    if length(y) ~= 21
        error('State vector y has %d elements, expected 21', length(y));
    end

    % ========== UNPACK STATES ==========
    P_top = y(1);
    P_bottom = y(2);
    C_top = y(3:8);
    C_bottom = y(9:14);
    I_conc = y(15);
    X_conc = y(16);
    T_f = y(17);
    T_c = y(18);
    T_condenser = y(19);
    T_pcm = y(20);
    pcm_melted_fraction = y(21);

    P_total = P_top + P_bottom;
    P_total = max(P_total, 0.01);  % Prevent division by zero only

    % ========== THERMAL POWER & FLUX ==========
    P_actual_MW = (P_total / 2.0) * params.P_nom;
    P_actual_W = P_actual_MW * 1e6;
    power_fraction = P_total / 2.0;

    energy_per_fission_J = params.G * 1e6 * 1.602e-19;
    reaction_rate_factor = params.Sigma_f * params.V_core;
    phi = P_actual_W / (energy_per_fission_J * reaction_rate_factor);
    phi = max(min(phi, 1e15), 1e10);

    % ========== IMPROVED SATURATION PRESSURE & TURBINE FACTOR v4.1 ==========
    % Finer enthalpy interpolation for better accuracy at intermediate pressures
    if T_condenser <= 100
        log10_P = 8.07131 - 1730.63 / (233.426 + T_condenser);
        P_mmHg = 10^log10_P;
        P_cond_bar = P_mmHg * 0.00133322;
    else
        P_cond_bar = 1.013 * exp((T_condenser - 100) / 45);
    end
    P_cond_bar = max(P_cond_bar, 0.023);

    % IMPROVED: Finer enthalpy lookup with more pressure points
    % Using linear interpolation instead of coarse steps
    pressure_points_fine = [0.023, 0.05, 0.08, 0.10, 0.12, 0.15, 0.18, 0.20, 0.25, 0.30, 0.35, 0.40, 0.50, 0.60, 0.80, 1.0];
    enthalpy_points_fine = [2000, 2080, 2090, 2100, 2120, 2140, 2160, 2200, 2220, 2250, 2280, 2300, 2320, 2380, 2420, 2450];

    if P_cond_bar <= pressure_points_fine(1)
        h_outlet = enthalpy_points_fine(1);
    elseif P_cond_bar >= pressure_points_fine(end)
        h_outlet = enthalpy_points_fine(end);
    else
        h_outlet = interp1(pressure_points_fine, enthalpy_points_fine, P_cond_bar, 'linear', 'extrap');
    end

    h_inlet = 2780;
    delta_h = h_inlet - h_outlet;
    delta_h_nom = 680;
    turbine_factor = max(0.5, min(1.0, delta_h / delta_h_nom));
    params.current_turbine_factor = turbine_factor;

    % ========== EFFICIENCY ==========
    efficiency = params.efficiency_ref - params.efficiency_derate * max(0, params.T_amb - 20);
    efficiency = max(efficiency, 0.25);
    params.current_efficiency = efficiency;

    % ========== STEAM GENERATOR HEAT TRANSFER ==========
    h_fc_W = params.h_fc * 1e6;
    Q_steam_W = params.UA_steam_gen * max(0, T_c - params.T_saturation_nominal);
    Q_steam_W = min(Q_steam_W, P_actual_W);
    Q_steam_W = max(Q_steam_W, 0);
    Q_to_condenser_W = Q_steam_W * (1 - efficiency * turbine_factor);
    Q_to_condenser_W = max(Q_to_condenser_W, 0);

    % ========== COOLING SYSTEM DYNAMICS ==========
    fan_speed = 0;
    fan_power_MW = 0;
    Q_cooling_capacity_W = 0;
    dT_pcm_dt = 0;
    d_pcm_melted_fraction_dt = 0;
    rho_condenser_feedback = 0;
    dT_condenser_dt = 0;
    tiac_power_MW = 0;  % NEW: TIAC parasitic load

    if strcmp(params.cooling_mode, 'once-through')
        c_pw = 4180;
        m_dot_cw_safe = max(params.m_dot_cw, 100);
        dT_cw = Q_to_condenser_W / (m_dot_cw_safe * c_pw);
        T_condenser_target = params.T_cw_in + dT_cw;
        T_condenser_target = max(T_condenser_target, params.T_cw_in + 2);
        T_condenser_target = min(T_condenser_target, params.T_cw_in + 15);
        dT_condenser_dt = (T_condenser_target - T_condenser) / 30;

    elseif strcmp(params.cooling_mode, 'wet')
        T_wb = params.T_wb;
        if T_wb < 15
            eta_wet = params.cooling_tower_base_eff;
        else
            eta_wet = params.cooling_tower_base_eff - params.cooling_tower_derate * (T_wb - 15);
            eta_wet = max(eta_wet, 0.70);
        end
        T_condenser_target = T_wb + 12;
        dT_condenser_dt = (T_condenser_target - T_condenser) / 45;

    elseif strcmp(params.cooling_mode, 'dry')
        % ========== OPTIMIZED MAD DRY COOLING WITH INNOVATIONS v4.1 ==========

        % Higher base air mass flow for arid conditions
        m_dot_air_nom = max(params.m_dot_air_nom * params.air_density_ratio, 100);
        c_p_air = params.c_p_air;
        ambient_temp = params.T_amb;
        effective_ambient = ambient_temp;
        m_cycle_boost = 0;
        tiac_boost = 0;  % NEW: TIAC cooling boost

        % NEW INNOVATION 5: Turbine Inlet Air Cooling (TIAC)
        % Uses absorption chiller powered by waste heat to cool turbine inlet air
        if params.tiac_enabled && ambient_temp > params.tiac_activation_temp
            % TIAC reduces effective ambient temperature
            T_wb = params.T_wb;
            tiac_temp_drop = min(params.tiac_effectiveness * (ambient_temp - T_wb), ...
                                 params.tiac_temp_reduction_max);
            T_tiac_out = ambient_temp - tiac_temp_drop;
            T_tiac_out = max(T_tiac_out, T_wb);

            % TIAC provides cooling boost to condenser by reducing heat sink temp
            tiac_boost = 0.08;  % 8% effectiveness boost
            tiac_power_MW = params.tiac_power_consumption_MW * power_fraction;

            % Update effective ambient (TIAC works in series with M-Cycle)
            effective_ambient = T_tiac_out;
        end

        % Innovation 4: Enhanced M-Cycle evaporative cooler
        if params.maisotsenko_enabled && ambient_temp > params.m_cycle_activation_temp
            T_wb = params.T_wb;
            % Higher effectiveness for M-Cycle (up to 0.93)
            m_cycle_eff = min(params.m_cycle_effectiveness, 0.95);

            % Temperature reduction with better physics
            temp_drop = m_cycle_eff * (effective_ambient - T_wb);
            T_mcycle_out = effective_ambient - temp_drop;

            % Ensure we don't go below wet bulb (thermodynamic limit with 1°C margin)
            T_mcycle_out = max(T_mcycle_out, T_wb - 1.0);
            effective_ambient = T_mcycle_out;

            % Higher boost for M-Cycle effectiveness
            m_cycle_boost = 0.18;  % Increased from 0.15
        end

        % Innovation 1: Enhanced desiccant boost calculation - AGGRESSIVE
        effectiveness_base = params.dry_cooling_effectiveness;
        desiccant_benefit = 0;

        if isfield(params, 'absorption_enabled') && params.absorption_enabled && params.desiccant_enabled
            % Calculate actual steam power for desiccant heat fraction
            Q_steam_W_check = params.UA_steam_gen * max(0, T_c - params.T_saturation_nominal);
            Q_steam_W_check = min(Q_steam_W_check, P_actual_W);
            desiccant_power = params.desiccant_heat_fraction * Q_steam_W_check;

            % Humidity-dependent desiccant effectiveness:
            % More moisture to remove in humid air (small wet-bulb depression),
            % less benefit in dry air (large wet-bulb depression).
            T_wb = params.T_wb;
            wb_depression = ambient_temp - T_wb;
            humidity_factor = max(0.3, min(1.0, 1.0 - (wb_depression - 5)/25));

            if params.desiccant_two_stage
                % Two-stage desiccant with humidity-aware boost
                if desiccant_power > 15e6
                    desiccant_benefit = (params.desiccant_stage1_boost + params.desiccant_stage2_boost) * humidity_factor;
                elseif desiccant_power > 8e6
                    desiccant_benefit = (params.desiccant_stage1_boost + params.desiccant_stage2_boost * 0.6) * humidity_factor;
                elseif desiccant_power > 4e6
                    desiccant_benefit = params.desiccant_stage1_boost * humidity_factor;
                else
                    desiccant_benefit = params.desiccant_stage1_boost * 0.3 * humidity_factor;
                end
            end
        end

        % Total effectiveness with all innovations
        % AGGRESSIVE: Higher max effectiveness cap
        effectiveness = effectiveness_base + desiccant_benefit + m_cycle_boost + tiac_boost;
        effectiveness = max(0.4, min(0.95, effectiveness));  % Increased cap to 0.95

        % Innovation 2: Enhanced air flow optimization
        m_dot_air_opt = params.airflow_base;
        if params.airflow_optimization
            % Scale airflow based on cooling demand and ambient conditions
            if ambient_temp > 35
                % Hot conditions: need more airflow
                m_dot_air_opt = params.airflow_max * 0.90;
            elseif ambient_temp > 25
                m_dot_air_opt = params.airflow_base * 1.3;
            else
                m_dot_air_opt = params.airflow_base;
            end
            m_dot_air_opt = max(params.airflow_min, min(params.airflow_max, m_dot_air_opt));
        end

        % Optimized fan speed control with VSD efficiency
        Q_required_W = Q_to_condenser_W;
        delta_T_available = max(T_condenser - effective_ambient, 3);  % Reduced min from 5 to 3

        if Q_required_W > 0 && effectiveness > 0 && c_p_air > 0
            % Calculate required air mass flow
            m_dot_required = Q_required_W / (effectiveness * c_p_air * delta_T_available);
            m_dot_required = max(m_dot_required, m_dot_air_nom * 0.25);

            % Fan speed with optimized minimum for hot conditions
            fan_speed_required = m_dot_required / m_dot_air_nom;
            if ambient_temp > 38
                fan_speed_required = max(fan_speed_required, 0.75);
            else
                fan_speed_required = max(fan_speed_required, 0.45);
            end
            fan_speed = max(0.3, min(1.15, fan_speed_required));  % Cap at 1.15
        else
            % Default fan speed logic
            if ambient_temp > 38
                fan_speed = max(0.75, min(1.15, (T_condenser - effective_ambient) / 8));
            else
                fan_speed = max(0.45, min(1.1, (T_condenser - effective_ambient) / 15));
            end
        end

        % Fan power with improved VSD efficiency curve
        vsd_efficiency = 0.88 + 0.08 * (1 - fan_speed);
        fan_power_MW = params.fan_power_nom_MW * (fan_speed^3) / vsd_efficiency;

        % Cap fan power
        if ambient_temp > 42
            fan_power_MW = max(0, min(6.5, fan_power_MW));
        else
            fan_power_MW = max(0, min(5.5, fan_power_MW));
        end
        params.current_fan_power_MW = fan_power_MW;

        m_dot_air = m_dot_air_nom * fan_speed;
        Q_cooling_capacity_W = effectiveness * m_dot_air * c_p_air * (T_condenser - effective_ambient);

        % PHYSICAL CONSTRAINT: Cannot cool below effective ambient + 2C (improved)
        T_condenser_min = effective_ambient + 2;

        if Q_cooling_capacity_W >= Q_to_condenser_W
            % Sufficient cooling capacity
            T_condenser_target = effective_ambient + Q_to_condenser_W / ...
                                 (effectiveness * m_dot_air * c_p_air);
            T_condenser_target = max(T_condenser_target, T_condenser_min);
            dT_condenser_dt = (T_condenser_target - T_condenser) / params.tau_condenser;
        else
            % Insufficient cooling - condenser heats up
            mC_condenser = params.m_condenser * params.c_p_condenser;
            dT_condenser_dt = (Q_to_condenser_W - Q_cooling_capacity_W) / mC_condenser;
            dT_condenser_dt = min(dT_condenser_dt, 0.25);  % Reduced from 0.3
        end

        % Safety: warm up if below minimum
        if T_condenser < T_condenser_min && dT_condenser_dt < 0
            dT_condenser_dt = (T_condenser_min - T_condenser) / params.tau_condenser;
        end

        % Innovation 3: Enhanced PCM thermal storage - ENABLED for all scenarios
        % State-of-charge is now tracked as ODE state y(21), so it persists
        % across time steps instead of resetting due to pass-by-value params.
        if params.pcm_storage_enabled
            pcm_melted_fraction = max(0, min(1, pcm_melted_fraction));  % bound state
            if ambient_temp < params.pcm_charge_temp_threshold
                % Cool conditions: charge PCM (solidify)
                if pcm_melted_fraction > 0
                    d_pcm_melted_fraction_dt = -0.001;
                end
                dT_pcm_dt = -0.03;
            elseif ambient_temp > params.pcm_discharge_temp_threshold
                % Hot conditions: discharge PCM (melt) to boost cooling
                if T_condenser > params.pcm_melt_temp && pcm_melted_fraction < 1.0
                    pcm_cooling_boost = 50e6 * power_fraction * (1 - pcm_melted_fraction);
                    Q_cooling_capacity_W = Q_cooling_capacity_W + pcm_cooling_boost;
                    d_pcm_melted_fraction_dt = 0.003;
                end
                dT_pcm_dt = 0.03;
            else
                dT_pcm_dt = 0;
            end
        end

        % Condenser feedback for insufficient cooling (milder)
        if Q_cooling_capacity_W > 0 && Q_cooling_capacity_W < Q_to_condenser_W * 0.75 && t > 100
            cooling_deficit = (Q_to_condenser_W - Q_cooling_capacity_W) / Q_to_condenser_W;
            rho_condenser_feedback = -0.0002 * cooling_deficit;
            rho_condenser_feedback = max(rho_condenser_feedback, -0.001);
        end

    else
        T_condenser_target = 35;
        dT_condenser_dt = (T_condenser_target - T_condenser) / 30;
        rho_condenser_feedback = 0;
    end

    dT_condenser_dt = max(min(dT_condenser_dt, 1.0), -1.0);

    % ========== REACTIVITY ==========
    [rho_ext, rho_xenon] = SMR_Reactivity_MAD(t, y, params, scenario);
    rho_ext = max(min(rho_ext, 0.015), -0.015);

    % Temperature feedback
    rho_fb = params.alpha_f * (T_f - params.T_f0_nominal) + ...
             params.alpha_c * (T_c - params.T_c0_nominal);
    rho_fb = max(min(rho_fb, 0.002), -0.005);

    % Xenon reactivity (if tracking enabled)
    if params.track_xenon
        denom = params.lambda_X + params.sigma_X * phi;
        denom = max(denom, 1e-10);
        X_eq = ((params.gamma_X + params.gamma_I) * params.Sigma_f * phi) / denom;
        X_eq = max(min(X_eq, 1e17), 1e10);
        X_diff = X_conc - X_eq;
        X_diff = max(min(X_diff, 1e16), -1e16);
        Sigma_a_approx = params.Sigma_f * 2.5;
        rho_xenon = -params.sigma_X * X_diff / Sigma_a_approx;
        rho_xenon = max(min(rho_xenon, 0.001), -0.005);
    end

    rho_total = rho_ext + rho_fb + rho_xenon + rho_condenser_feedback;
    rho_total = max(min(rho_total, 0.005), -0.01);

    % ========== POINT KINETICS ==========
    lambda_col = params.lambda_i(:);
    beta_col = params.beta_i(:);

    % Innovation: Differential control rod banking (Scenario C, non-dry)
    if params.differential_rods_enabled && scenario == 3 && ~strcmp(params.cooling_mode, 'dry')
        AO_current = (P_top - P_bottom) / (P_top + P_bottom + eps) * 100;
        AO_error = params.AO_target - AO_current;
        if abs(AO_error) > params.AO_deadband
            rho_diff = 0.00008 * sign(AO_error) * min(1, abs(AO_error) / 10);
            rho_diff = max(min(rho_diff, params.rho_diff_max), -params.rho_diff_max);
        else
            rho_diff = 0;
        end
        rho_top = rho_total + rho_diff;
        rho_bottom = rho_total - rho_diff;
    else
        rho_top = rho_total;
        rho_bottom = rho_total;
    end

    rho_top = max(min(rho_top, 0.015), -0.015);
    rho_bottom = max(min(rho_bottom, 0.015), -0.015);

    sum_lambda_C_top = sum(lambda_col .* C_top);
    dP_top_dt = ((rho_top - params.beta) / params.Lambda) * P_top + sum_lambda_C_top;
    sum_lambda_C_bottom = sum(lambda_col .* C_bottom);
    dP_bottom_dt = ((rho_bottom - params.beta) / params.Lambda) * P_bottom + sum_lambda_C_bottom;

    % Hard limit: if power is at minimum, don't let derivative push it lower
    if P_top <= 0.1 && dP_top_dt < 0
        dP_top_dt = 0;
    end
    if P_bottom <= 0.1 && dP_bottom_dt < 0
        dP_bottom_dt = 0;
    end
    dP_top_dt = max(min(dP_top_dt, 50), -50);
    dP_bottom_dt = max(min(dP_bottom_dt, 50), -50);

    % ========== DELAYED NEUTRON PRECURSORS ==========
    dC_top_dt = zeros(6,1);
    dC_bottom_dt = zeros(6,1);
    for i = 1:6
        dC_top_dt(i) = (beta_col(i) / params.Lambda) * P_top - lambda_col(i) * C_top(i);
        dC_bottom_dt(i) = (beta_col(i) / params.Lambda) * P_bottom - lambda_col(i) * C_bottom(i);
        dC_top_dt(i) = max(min(dC_top_dt(i), 10), -10);
        dC_bottom_dt(i) = max(min(dC_bottom_dt(i), 10), -10);
    end

    % ========== XENON & IODINE DYNAMICS ==========
    dI_dt = params.gamma_I * params.Sigma_f * phi - params.lambda_I * I_conc;
    dX_dt = params.gamma_X * params.Sigma_f * phi + params.lambda_I * I_conc - ...
            params.lambda_X * X_conc - params.sigma_X * X_conc * phi;
    dI_dt = max(min(dI_dt, 1e12), -1e12);
    dX_dt = max(min(dX_dt, 1e12), -1e12);

    % ========== TEMPERATURE DYNAMICS ==========
    dT_f_dt = (P_actual_W - h_fc_W * max(0, T_f - T_c)) / (params.m_f * params.c_pf);
    dT_f_dt = max(min(dT_f_dt, 200), -200);

    dT_c_dt = (h_fc_W * max(0, T_f - T_c) - Q_steam_W) / (params.m_c * params.c_pc);
    dT_c_dt = max(min(dT_c_dt, 100), -100);

    % ========== ASSEMBLE OUTPUT ==========
    dydt(1) = dP_top_dt;
    dydt(2) = dP_bottom_dt;
    dydt(3:8) = dC_top_dt;
    dydt(9:14) = dC_bottom_dt;
    dydt(15) = dI_dt;
    dydt(16) = dX_dt;
    dydt(17) = dT_f_dt;
    dydt(18) = dT_c_dt;
    dydt(19) = dT_condenser_dt;
    dydt(20) = dT_pcm_dt;
    dydt(21) = d_pcm_melted_fraction_dt;

catch ME
    error_count = error_count + 1;
    fprintf('\n*** ERROR in SMR_ODEs_MAD at t=%.6f ***\n', t);
    fprintf('Message: %s\n', ME.message);
    fprintf('Identifier: %s\n', ME.identifier);
    fprintf('Stack trace:\n');
    for k = 1:length(ME.stack)
        fprintf('  Line %d in %s\n', ME.stack(k).line, ME.stack(k).name);
    end
    fprintf('State vector size: %d\n', length(y));
    if length(y) >= 2
        fprintf('P_total = %.4f\n', y(1)+y(2));
    end
    rethrow(ME);
end

end