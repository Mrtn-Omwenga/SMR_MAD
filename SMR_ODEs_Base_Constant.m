function dydt = SMR_ODEs_MAD_Constant(t, y, params, scenario, P_demand_fixed)
% SMR_ODEs_MAD_Constant.m - MAD ODEs with constant demand
% FIXED: Accepts P_demand_fixed as 5th parameter
% FIXED: Gentler PID gains for partial load stability

% Default P_demand_fixed if not provided
if nargin < 5 || isempty(P_demand_fixed)
    P_demand_fixed = 0.78;
end

dydt = zeros(20,1);

% Unpack states
P_top = max(min(y(1), 1.25), 0.005);
P_bottom = max(min(y(2), 1.25), 0.005);
C_top = y(3:8);
C_bottom = y(9:14);
I_conc = y(15);
X_conc = y(16);
T_f = y(17);
T_c = y(18);
T_condenser = y(19);
T_pcm = y(20);

P_total = P_top + P_bottom;
P_total = max(min(P_total, 2.4), 0.1);

% Thermal power & flux
P_actual_MW = (P_total / 2.0) * params.P_nom;
P_actual_W = P_actual_MW * 1e6;
power_fraction = P_total / 2.0;

energy_per_fission_J = params.G * 1e6 * 1.602e-19;
reaction_rate_factor = params.Sigma_f * params.V_core;
phi = P_actual_W / (energy_per_fission_J * reaction_rate_factor);
phi = max(min(phi, 1e15), 1e10);

% Saturation pressure & turbine factor
if T_condenser <= 100
    log10_P = 8.07131 - 1730.63 / (233.426 + T_condenser);
    P_mmHg = 10^log10_P;
    P_cond_bar = P_mmHg * 0.00133322;
else
    P_cond_bar = 1.013 * exp((T_condenser - 100) / 45);
end
P_cond_bar = max(P_cond_bar, 0.023);

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

% Efficiency
efficiency = params.efficiency_ref - params.efficiency_derate * max(0, params.T_amb - 20);
efficiency = max(efficiency, 0.25);
params.current_efficiency = efficiency;

% Steam generator heat transfer
h_fc_W = params.h_fc * 1e6;
Q_steam_W = params.UA_steam_gen * max(0, T_c - params.T_saturation_nominal);
Q_steam_W = min(Q_steam_W, P_actual_W);
Q_steam_W = max(Q_steam_W, 0);
Q_to_condenser_W = Q_steam_W * (1 - efficiency * turbine_factor);
Q_to_condenser_W = max(Q_to_condenser_W, 0);

% Cooling system dynamics
fan_speed = 0;
fan_power_MW = 0;
Q_cooling_capacity_W = 0;
dT_pcm_dt = 0;
rho_condenser_feedback = 0;
dT_condenser_dt = 0;

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
    % MAD dry cooling with innovations
    m_dot_air_nom = max(params.m_dot_air_nom * params.air_density_ratio, 100);
    c_p_air = params.c_p_air;
    ambient_temp = params.T_amb;
    effective_ambient = ambient_temp;
    m_cycle_boost = 0;
    tiac_boost = 0;

    % TIAC
    if params.tiac_enabled && ambient_temp > params.tiac_activation_temp
        T_wb = params.T_wb;
        tiac_temp_drop = min(params.tiac_effectiveness * (ambient_temp - T_wb), ...
                             params.tiac_temp_reduction_max);
        T_tiac_out = ambient_temp - tiac_temp_drop;
        T_tiac_out = max(T_tiac_out, T_wb);
        effective_ambient = T_tiac_out;
        tiac_boost = 0.08;
    end

    % M-Cycle
    if params.maisotsenko_enabled && ambient_temp > params.m_cycle_activation_temp
        T_wb = params.T_wb;
        m_cycle_eff = min(params.m_cycle_effectiveness, 0.95);
        temp_drop = m_cycle_eff * (effective_ambient - T_wb);
        T_mcycle_out = effective_ambient - temp_drop;
        T_mcycle_out = max(T_mcycle_out, T_wb - 1.0);
        effective_ambient = T_mcycle_out;
        m_cycle_boost = 0.18;
    end

    % Desiccant
    effectiveness_base = params.dry_cooling_effectiveness;
    desiccant_benefit = 0;

    if isfield(params, 'absorption_enabled') && params.absorption_enabled && params.desiccant_enabled
        Q_steam_W_check = params.UA_steam_gen * max(0, T_c - params.T_saturation_nominal);
        Q_steam_W_check = min(Q_steam_W_check, P_actual_W);
        desiccant_power = params.desiccant_heat_fraction * Q_steam_W_check;

        if params.desiccant_two_stage
            if desiccant_power > 15e6
                desiccant_benefit = params.desiccant_stage1_boost + params.desiccant_stage2_boost;
            elseif desiccant_power > 8e6
                desiccant_benefit = params.desiccant_stage1_boost + params.desiccant_stage2_boost * 0.6;
            elseif desiccant_power > 4e6
                desiccant_benefit = params.desiccant_stage1_boost;
            else
                desiccant_benefit = params.desiccant_stage1_boost * 0.3;
            end
        end
    end

    % Total effectiveness
    effectiveness = effectiveness_base + desiccant_benefit + m_cycle_boost + tiac_boost;
    effectiveness = max(0.4, min(0.95, effectiveness));

    % Air flow
    m_dot_air_opt = params.airflow_base;
    if params.airflow_optimization
        if ambient_temp > 35
            m_dot_air_opt = params.airflow_max * 0.90;
        elseif ambient_temp > 25
            m_dot_air_opt = params.airflow_base * 1.3;
        end
        m_dot_air_opt = max(params.airflow_min, min(params.airflow_max, m_dot_air_opt));
    end

    % Fan speed
    Q_required_W = Q_to_condenser_W;
    delta_T_available = max(T_condenser - effective_ambient, 3);

    if Q_required_W > 0 && effectiveness > 0 && c_p_air > 0
        m_dot_required = Q_required_W / (effectiveness * c_p_air * delta_T_available);
        m_dot_required = max(m_dot_required, m_dot_air_nom * 0.25);
        fan_speed_required = m_dot_required / m_dot_air_nom;
        if ambient_temp > 38
            fan_speed_required = max(fan_speed_required, 0.75);
        else
            fan_speed_required = max(fan_speed_required, 0.45);
        end
        fan_speed = max(0.3, min(1.15, fan_speed_required));
    else
        if ambient_temp > 38
            fan_speed = max(0.75, min(1.15, (T_condenser - effective_ambient) / 8));
        else
            fan_speed = max(0.45, min(1.1, (T_condenser - effective_ambient) / 15));
        end
    end

    % Fan power with VSD
    vsd_efficiency = 0.88 + 0.08 * (1 - fan_speed);
    fan_power_MW = params.fan_power_nom_MW * (fan_speed^3) / vsd_efficiency;
    if ambient_temp > 42
        fan_power_MW = max(0, min(6.5, fan_power_MW));
    else
        fan_power_MW = max(0, min(5.5, fan_power_MW));
    end
    params.current_fan_power_MW = fan_power_MW;

    m_dot_air = m_dot_air_nom * fan_speed;
    Q_cooling_capacity_W = effectiveness * m_dot_air * c_p_air * (T_condenser - effective_ambient);

    % Physical constraint
    T_condenser_min = effective_ambient + 2;

    if Q_cooling_capacity_W >= Q_to_condenser_W
        T_condenser_target = effective_ambient + Q_to_condenser_W / ...
                             (effectiveness * m_dot_air * c_p_air);
        T_condenser_target = max(T_condenser_target, T_condenser_min);
        dT_condenser_dt = (T_condenser_target - T_condenser) / params.tau_condenser;
    else
        mC_condenser = params.m_condenser * params.c_p_condenser;
        dT_condenser_dt = (Q_to_condenser_W - Q_cooling_capacity_W) / mC_condenser;
        dT_condenser_dt = min(dT_condenser_dt, 0.25);
    end

    if T_condenser < T_condenser_min && dT_condenser_dt < 0
        dT_condenser_dt = (T_condenser_min - T_condenser) / params.tau_condenser;
    end

    % PCM storage
    if params.pcm_storage_enabled
        if ambient_temp < params.pcm_charge_temp_threshold
            params.pcm_melted_fraction = max(0, params.pcm_melted_fraction - 0.001);
            dT_pcm_dt = -0.03;
        elseif ambient_temp > params.pcm_discharge_temp_threshold
            if T_condenser > params.pcm_melt_temp && params.pcm_melted_fraction < 1.0
                pcm_cooling_boost = 50e6 * power_fraction * (1 - params.pcm_melted_fraction);
                Q_cooling_capacity_W = Q_cooling_capacity_W + pcm_cooling_boost;
                params.pcm_melted_fraction = min(1, params.pcm_melted_fraction + 0.003);
            end
            dT_pcm_dt = 0.03;
        else
            dT_pcm_dt = 0;
        end
        T_pcm = max(params.pcm_melt_temp - 5, min(params.pcm_melt_temp + 5, T_pcm));
    end

    % Condenser feedback
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

% ========== REACTIVITY WITH FIXED DEMAND ==========
[rho_ext, rho_xenon] = calc_reactivity_mad_constant(t, y, params, scenario, P_demand_fixed);

% Temperature feedback
rho_fb = params.alpha_f * (T_f - params.T_f0_nominal) + ...
         params.alpha_c * (T_c - params.T_c0_nominal);
rho_fb = max(min(rho_fb, 0.002), -0.005);

% Xenon reactivity (if tracking enabled)
if params.track_xenon
    denom = params.lambda_X + params.sigma_X * phi;
    denom = max(denom, 1e-10);
    X_eq = (params.gamma_X * params.Sigma_f * phi) / denom;
    X_eq = max(min(X_eq, 1e17), 1e10);
    X_diff = X_conc - X_eq;
    X_diff = max(min(X_diff, 1e16), -1e16);
    Sigma_a_approx = params.Sigma_f * 2.5;
    rho_xenon = -params.sigma_X * X_diff / Sigma_a_approx;
    rho_xenon = max(min(rho_xenon, 0.001), -0.005);
end

rho_total = rho_ext + rho_fb + rho_xenon + rho_condenser_feedback;
rho_total = max(min(rho_total, 0.005), -0.01);

% Point Kinetics
lambda_col = params.lambda_i(:);
beta_col = params.beta_i(:);

% Differential rods
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

if P_top <= 0.1 && dP_top_dt < 0
    dP_top_dt = 0;
end
if P_bottom <= 0.1 && dP_bottom_dt < 0
    dP_bottom_dt = 0;
end
dP_top_dt = max(min(dP_top_dt, 50), -50);
dP_bottom_dt = max(min(dP_bottom_dt, 50), -50);

% Delayed neutron precursors
dC_top_dt = zeros(6,1);
dC_bottom_dt = zeros(6,1);
for i = 1:6
    dC_top_dt(i) = (beta_col(i) / params.Lambda) * P_top - lambda_col(i) * C_top(i);
    dC_bottom_dt(i) = (beta_col(i) / params.Lambda) * P_bottom - lambda_col(i) * C_bottom(i);
    dC_top_dt(i) = max(min(dC_top_dt(i), 10), -10);
    dC_bottom_dt(i) = max(min(dC_bottom_dt(i), 10), -10);
end

% Xenon & Iodine
dI_dt = params.gamma_I * params.Sigma_f * phi - params.lambda_I * I_conc;
dX_dt = params.gamma_X * params.Sigma_f * phi + params.lambda_I * I_conc - ...
        params.lambda_X * X_conc - params.sigma_X * X_conc * phi;
dI_dt = max(min(dI_dt, 1e12), -1e12);
dX_dt = max(min(dX_dt, 1e12), -1e12);

% Temperature dynamics
dT_f_dt = (P_actual_W - h_fc_W * max(0, T_f - T_c)) / (params.m_f * params.c_pf);
dT_f_dt = max(min(dT_f_dt, 200), -200);

dT_c_dt = (h_fc_W * max(0, T_f - T_c) - Q_steam_W) / (params.m_c * params.c_pc);
dT_c_dt = max(min(dT_c_dt, 100), -100);

% Assemble output
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

end

%% =========================================================================
% EMBEDDED REACTIVITY FUNCTION - FIXED with gentler gains
%% =========================================================================

function [rho_ext, rho_xenon] = calc_reactivity_mad_constant(t, y, params, scenario, P_demand_fixed)

rho_xenon = 0;

% Unpack states
P_top = y(1);
P_bottom = y(2);
T_f = y(17);
T_c = y(18);
P_total = P_top + P_bottom;

if scenario == 3
    % Use CONSTANT demand
    P_demand = P_demand_fixed;
    P_norm = P_total / 2.0;
    error_signal = P_demand - P_norm;

    % ========== GAIN-SCHEDULED PID - GENTLER FOR PARTIAL LOAD ==========
    if params.gain_scheduling_enabled
        power_frac = P_norm;
        % FIXED: Gentler gains, especially at low power
        if power_frac < 0.6
            Kp = 0.0008;   Ki = 0.00004;  Kd = 0.000008;
        elseif power_frac < 0.85
            Kp = 0.0012;   Ki = 0.00006;  Kd = 0.000012;
        else
            Kp = 0.0025;   Ki = 0.00012;  Kd = 0.000025;
        end
    else
        Kp = 0.0012;
        Ki = 0.00006;
        Kd = 0.000012;
    end

    rho_p = Kp * error_signal;

    % FIXED: Smaller integral windup limit
    tau_i = 1500;
    rho_i = Ki * error_signal * min(t, tau_i);
    rho_i = max(min(rho_i, 0.003), -0.003);

    dP_demand_dt = 0;  % Constant demand, no derivative
    rho_d = Kd * dP_demand_dt;

    rho_ext = rho_p + rho_i + rho_d;
    rho_ext = max(min(rho_ext, 0.008), -0.008);

else
    % Scenarios A and B
    if t < params.demand_ramp_up_start
        rho_ext = 0;
    elseif t < params.demand_ramp_up_end
        fraction = (t - params.demand_ramp_up_start) / ...
                   (params.demand_ramp_up_end - params.demand_ramp_up_start);
        rho_ext = params.demand_magnitude * fraction;
    elseif t < params.demand_hold_end
        rho_ext = params.demand_magnitude;
    elseif t < params.demand_ramp_down_end
        fraction = 1 - (t - params.demand_hold_end) / ...
                   (params.demand_ramp_down_end - params.demand_hold_end);
        rho_ext = params.demand_magnitude * fraction;
    else
        rho_ext = 0;
    end
end

end