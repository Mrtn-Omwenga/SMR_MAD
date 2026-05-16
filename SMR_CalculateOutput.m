function [net_MWe, gross_MWe, turbine_factor, fan_power_MW, effectiveness, fan_speed] = ...
    SMR_CalculateOutput(P_total, T_cond, params)
% SMR_CalculateOutput.m - Centralized post-processing for all scripts
% Calculates electrical output from thermal state
% FIXED: Handles missing fields in Base Model params

    % Turbine factor from condenser temperature
    if T_cond <= 100
        log10_P = 8.07131 - 1730.63 / (233.426 + T_cond);
        P_mmHg = 10^log10_P;
        P_cond_bar = P_mmHg * 0.00133322;
    else
        P_cond_bar = 1.013 * exp((T_cond - 100) / 45);
    end
    P_cond_bar = max(P_cond_bar, 0.023);

    pressure_points = [0.023, 0.05, 0.08, 0.10, 0.12, 0.15, 0.18, 0.20, ...
                       0.25, 0.30, 0.35, 0.40, 0.50, 0.60, 0.80, 1.0];
    enthalpy_points = [2000, 2080, 2090, 2100, 2120, 2140, 2160, 2200, ...
                       2220, 2250, 2280, 2300, 2320, 2380, 2420, 2450];

    if P_cond_bar <= pressure_points(1)
        h_outlet = enthalpy_points(1);
    elseif P_cond_bar >= pressure_points(end)
        h_outlet = enthalpy_points(end);
    else
        h_outlet = interp1(pressure_points, enthalpy_points, P_cond_bar, 'linear', 'extrap');
    end

    h_inlet = 2780;
    delta_h = h_inlet - h_outlet;
    delta_h_nom = 680;
    turbine_factor = max(0.5, min(1.0, delta_h / delta_h_nom));

    % Gross power
    power_fraction = P_total / 2.0;
    gross_MWe = power_fraction * params.P_elec_nom * turbine_factor;

    % Fan power and TIAC (same logic as ODE)
    fan_power_MW = 0;
    tiac_power_MW = 0;
    fan_speed = 0;

    if strcmp(params.cooling_mode, 'dry')
        T_amb_eff = params.T_amb;

        % Apply TIAC first (CHECK FIELD EXISTS)
        if isfield(params, 'tiac_enabled') && params.tiac_enabled && ...
           isfield(params, 'tiac_activation_temp') && params.T_amb > params.tiac_activation_temp && ...
           isfield(params, 'tiac_effectiveness') && isfield(params, 'tiac_temp_reduction_max') && ...
           isfield(params, 'tiac_power_consumption_MW') && isfield(params, 'T_wb')
            
            tiac_temp_drop = min(params.tiac_effectiveness * (params.T_amb - params.T_wb), ...
                                 params.tiac_temp_reduction_max);
            T_tiac_out = params.T_amb - tiac_temp_drop;
            T_tiac_out = max(T_tiac_out, params.T_wb);
            T_amb_eff = T_tiac_out;
            tiac_power_MW = params.tiac_power_consumption_MW * power_fraction;
        end

        % Apply M-Cycle (CHECK FIELD EXISTS)
        if isfield(params, 'maisotsenko_enabled') && params.maisotsenko_enabled && ...
           isfield(params, 'm_cycle_activation_temp') && params.T_amb > params.m_cycle_activation_temp && ...
           isfield(params, 'm_cycle_effectiveness') && isfield(params, 'T_wb')
            
            m_cycle_eff = min(params.m_cycle_effectiveness, 0.95);
            T_mcycle_out = T_amb_eff - m_cycle_eff * (T_amb_eff - params.T_wb);
            T_mcycle_out = max(T_mcycle_out, params.T_wb - 1.0);
            T_amb_eff = T_mcycle_out;
        end

        % Calculate fan speed based on effective ambient
        if T_cond > T_amb_eff
            delta_T = T_cond - T_amb_eff;
            if params.T_amb > 38
                fan_speed = max(0.75, min(1.15, delta_T / 8));
            else
                fan_speed = max(0.45, min(1.1, delta_T / 15));
            end
            
            % VSD efficiency
            vsd_eff = 0.88 + 0.08 * (1 - fan_speed);
            
            % Check field exists before using
            if isfield(params, 'fan_power_nom_MW')
                fan_power_MW = params.fan_power_nom_MW * (fan_speed^3) / vsd_eff;
            else
                fan_power_MW = 5.0 * (fan_speed^3) / vsd_eff;  % Default fallback
            end
            
            if params.T_amb > 42
                fan_power_MW = max(0, min(6.5, fan_power_MW));
            else
                fan_power_MW = max(0, min(5.5, fan_power_MW));
            end
        else
            fan_power_MW = 0;
        end
    end

    net_MWe = gross_MWe - fan_power_MW - tiac_power_MW;

    % Effectiveness estimate for reporting (CHECK ALL FIELDS)
    effectiveness_base = 0.65;  % Default base model
    if isfield(params, 'dry_cooling_effectiveness')
        effectiveness_base = params.dry_cooling_effectiveness;
    end
    
    des_benefit = 0;
    if isfield(params, 'absorption_enabled') && params.absorption_enabled && ...
       isfield(params, 'desiccant_enabled') && params.desiccant_enabled && ...
       isfield(params, 'desiccant_stage1_boost') && isfield(params, 'desiccant_stage2_boost')
        des_benefit = params.desiccant_stage1_boost + params.desiccant_stage2_boost;
    end
    
    mc_benefit = 0;
    if isfield(params, 'm_cycle_effectiveness')
        mc_benefit = 0.18 * params.m_cycle_effectiveness / 0.93;
    end
    
    tiac_benefit = 0;
    if isfield(params, 'tiac_enabled') && params.tiac_enabled
        tiac_benefit = 0.08;
    end
    
    effectiveness = min(0.95, effectiveness_base + des_benefit + mc_benefit + tiac_benefit);
end