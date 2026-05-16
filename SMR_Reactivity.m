function rho_ext = SMR_Reactivity(t, y, params, scenario)
% SMR_Reactivity.m v7 - FIXED for proper load-following
% Uses robust PID control (similar to MAD approach)

% Unpack states
P_top = y(1);
P_bottom = y(2);
T_f = y(17);
T_c = y(18);
P_total = P_top + P_bottom;

persistent integral_term prev_error prev_t;
if isempty(integral_term)
    integral_term = 0;
    prev_error = 0;
    prev_t = 0;
end

if scenario == 3
    % Get demand
    P_demand = SMR_Demand(t, params, scenario);
    P_norm = P_total / 2.0;
    error = P_demand - P_norm;

    % ========== ROBUST PID CONTROL (Fixed v7) ==========
    % Use stronger gains for faster settling
    Kp = 0.008;   % Increased from 0.003
    Ki = 0.001;   % Increased from 0.0005
    Kd = 0.002;   % Increased from 0.001

    % Proportional
    rho_p = Kp * error;

    % Integral with anti-windup
    dt = t - prev_t;
    if dt > 0
        integral_term = integral_term + Ki * error * dt;
        integral_term = max(min(integral_term, 0.02), -0.02);
    end
    rho_i = integral_term;

    % Derivative (on error rate)
    if dt > 0
        d_error = (error - prev_error) / dt;
        rho_d = Kd * d_error;
    else
        rho_d = 0;
    end

    % Feedforward based on demand level
    rho_ff = -0.005 * (P_demand - 1.0);  % Negative for lower power

    % Total external reactivity
    rho_ext = rho_p + rho_i + rho_d + rho_ff;

    % Rate limiting (physical control rod speed)
    max_rate = 0.0005;  % 50 pcm/s - faster than before
    persistent rho_ext_prev;
    if isempty(rho_ext_prev)
        rho_ext_prev = 0;
    end

    delta_rho = rho_ext - rho_ext_prev;
    if abs(delta_rho) > max_rate
        delta_rho = sign(delta_rho) * max_rate;
    end
    rho_ext = rho_ext_prev + delta_rho;
    rho_ext_prev = rho_ext;

    % Absolute limits
    rho_ext = max(min(rho_ext, 0.015), -0.015);

    % Update persistent variables
    prev_error = error;
    prev_t = t;

else
    % Scenarios A and B: Simple ramp profile
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