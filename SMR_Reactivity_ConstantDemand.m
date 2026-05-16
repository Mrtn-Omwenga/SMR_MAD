function rho_ext = SMR_Reactivity_ConstantDemand(t, y, params, scenario, P_demand_fixed)
% SMR_Reactivity_ConstantDemand.m - Reactivity with constant demand
% For rigorous comparison at fixed power level

% Unpack states
P_top = y(1);
P_bottom = y(2);
T_f = y(17);
T_c = y(18);
P_total = P_top + P_bottom;

persistent integral_term prev_error prev_t rho_ext_prev;
if isempty(integral_term)
    integral_term = 0;
    prev_error = 0;
    prev_t = 0;
    rho_ext_prev = 0;
end

if scenario == 3
    % Use CONSTANT demand instead of variable
    P_demand = P_demand_fixed;  % e.g., 0.78
    P_norm = P_total / 2.0;
    error = P_demand - P_norm;

    % Robust PID control
    Kp = 0.008;
    Ki = 0.001;
    Kd = 0.002;

    % Proportional
    rho_p = Kp * error;

    % Integral with anti-windup
    dt = t - prev_t;
    if dt > 0
        integral_term = integral_term + Ki * error * dt;
        integral_term = max(min(integral_term, 0.02), -0.02);
    end
    rho_i = integral_term;

    % Derivative
    if dt > 0
        d_error = (error - prev_error) / dt;
        rho_d = Kd * d_error;
    else
        rho_d = 0;
    end

    % Feedforward
    rho_ff = -0.005 * (P_demand - 1.0);

    % Total
    rho_ext = rho_p + rho_i + rho_d + rho_ff;

    % Rate limiting
    max_rate = 0.0005;
    delta_rho = rho_ext - rho_ext_prev;
    if abs(delta_rho) > max_rate
        delta_rho = sign(delta_rho) * max_rate;
    end
    rho_ext = rho_ext_prev + delta_rho;
    rho_ext_prev = rho_ext;

    % Limits
    rho_ext = max(min(rho_ext, 0.015), -0.015);

    % Update
    prev_error = error;
    prev_t = t;

else
    % Scenarios A and B - use original logic
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