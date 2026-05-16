function [rho_ext, rho_xenon] = SMR_Reactivity_MAD_ConstantDemand(t, y, params, scenario, P_demand_fixed)
% SMR_Reactivity_MAD_ConstantDemand.m - MAD reactivity with constant demand

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

    % Gain-scheduled PID
    if params.gain_scheduling_enabled
        power_frac = P_norm;
        if power_frac < 0.6
            Kp = 0.0015; Ki = 0.00008; Kd = 0.000015;
        elseif power_frac < 0.9
            Kp = 0.0025; Ki = 0.00012; Kd = 0.000025;
        else
            Kp = 0.0035; Ki = 0.00015; Kd = 0.000035;
        end
    else
        Kp = 0.0025; Ki = 0.00008; Kd = 0.00002;
    end

    rho_p = Kp * error_signal;

    tau_i = 1500;
    rho_i = Ki * error_signal * min(t, tau_i);
    rho_i = max(min(rho_i, 0.006), -0.006);

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