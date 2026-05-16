function [rho_ext, rho_xenon] = SMR_Reactivity_MAD(t, y, params, scenario)
% SMR_Reactivity_MAD.m - OPTIMIZED VERSION v4.1
% Enhanced PID control for load-following with better tracking

% Initialize outputs
rho_ext = 0;
rho_xenon = 0;

% Unpack states
P_top = y(1);
P_bottom = y(2);
T_f = y(17);
T_c = y(18);
P_total = P_top + P_bottom;

if scenario == 3
    % ========== SCENARIO C: LOAD-FOLLOWING WITH OPTIMIZED PID ==========

    % Get demand
    P_demand = 0.8;
    try
        P_demand = SMR_Demand(t, params, scenario);
    catch
        % Keep fallback
    end

    P_norm = P_total / 2.0;
    error_signal = P_demand - P_norm;

    % ========== GAIN-SCHEDULED PID - OPTIMIZED ==========
    if params.gain_scheduling_enabled
        power_frac = P_norm;
        if power_frac < 0.6
            Kp = 0.0015;   Ki = 0.00008;  Kd = 0.000015;
        elseif power_frac < 0.9
            Kp = 0.0025;   Ki = 0.00012;  Kd = 0.000025;
        else
            Kp = 0.0035;   Ki = 0.00015;  Kd = 0.000035;
        end
    else
        Kp = 0.0025;
        Ki = 0.00008;
        Kd = 0.00002;
    end

    % Proportional term
    rho_p = Kp * error_signal;

    % Integral term (stateless with anti-windup)
    tau_i = 1500;  % Reduced from 2000 for faster response
    rho_i = Ki * error_signal * min(t, tau_i);
    rho_i = max(min(rho_i, 0.006), -0.006);

    % Derivative term on demand rate (feedforward)
    dP_demand_dt = 0;
    try
        dP_demand_dt = SMR_DemandRate(t, params);
    catch
        % Keep zero
    end
    rho_d = Kd * dP_demand_dt;

    % Total external reactivity
    rho_ext = rho_p + rho_i + rho_d;

    % ========== RATE LIMITING ==========
    rho_ext = max(min(rho_ext, 0.008), -0.008);

else
    % ========== SCENARIOS A & B: Simple ramp profile ==========
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