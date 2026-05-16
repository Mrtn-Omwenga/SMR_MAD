function [rho_ext, rho_xenon, rod_data] = SMR_Reactivity(t, y, params, scenario)
% v11.0 - Stateless CRDM + T-avg Program for Load-Following
%
% CRITICAL FIX v11: Removed ALL persistent variables. MATLAB's ode15s evaluates
% the derivative function many times per step (Jacobian estimation, Newton
% iteration for implicit solve). Persistent state corrupts the solver's
% convergence because f(t,y) is no longer a pure function of (t,y).
%
% This version computes reactivity algebraically from the instantaneous state.
% The T-avg program and feedforward terms provide correct steady-state
% reactivity; proportional + stateless integral handle transients.
%
% PHYSICS BASIS:
%   - T-avg program: T_ref = T_nominal - 30*(1 - P_demand)
%   - Feedforward rho_ff balances temperature feedback at each power level
%   - Proportional gain Kp = 0.020 on power error
%   - Stateless integral: Ki*error*min(t, tau_i) (safe for adaptive solvers)
%
% Reference: Byun & Yim (2024), SMART-100 load-following analysis

%% Initialize outputs
rho_ext = 0;
rho_xenon = 0;
rod_data = struct('position', 0, 'worth', 0, 'demand_reactivity', 0, ...
                  'T_avg', 0, 'T_avg_error', 0);

%% Unpack states
P_norm = (y(1) + y(2)) / 2.0;
T_f = y(17);
T_c = y(18);

%% ========================================================================
% SCENARIO C: LOAD-FOLLOWING WITH CRDM + T-AVG PROGRAM
%% ========================================================================
if scenario == 3
    % Get demand profile
    P_demand = 0.8;
    try
        P_demand = SMR_Demand(t, params, scenario);
    catch ME
        fprintf('  [WARN] SMR_Demand error at t=%.3f: %s\n', t, ME.message);
        P_demand = 0.8;
    end

    % --- POWER TRACKING ERROR ---
    power_error = P_demand - P_norm;

    % --- T-AVG PROGRAM ---
    % Real PWRs: T_avg drops with load. Typical slope: 20-40 degC per unit.
    T_avg_slope = 30.0;
    T_avg_ref = params.T_avg_nominal - T_avg_slope * max(0, 1.0 - P_demand);
    T_avg_error = T_avg_ref - T_c;

    % --- FEEDFORWARD REACTIVITY ---
    % At steady state below ~85% power, reduced coolant temperature gives
    % positive feedback (~+0.002). Pre-compensate with negative reactivity.
    if P_demand < 0.85
        rho_ff = -0.002;
    else
        rho_ff = 0.0;
    end

    % --- PROPORTIONAL CONTROL ---
    Kp = 0.020;
    rho_p = Kp * power_error;

    % --- STATELESS INTEGRAL ---
    % Effective gain ramps from 0 to Ki*tau_i over tau_i seconds.
    % This is SAFE for adaptive solvers because t is constant during all
    % evaluations at a given solver step.
    Ki = 0.00002;
    tau_i = 5000;
    rho_i = Ki * power_error * min(t, tau_i);
    rho_i = max(min(rho_i, 0.008), -0.008);

    % --- TOTAL CRDM DEMAND ---
    rho_demand = rho_ff + rho_p + rho_i;

    % Clamp to physical rod worth (sin-squared curve peak = 0.015)
    rho_max = 0.015;
    rho_demand = max(min(rho_demand, rho_max), -rho_max);

    % --- ALGEBRAIC ROD POSITION (diagnostics only) ---
    % Compute the rod position that would produce rho_demand via the
    % sin-squared worth curve. No persistent state — purely algebraic.
    if abs(rho_demand) > 1e-10
        rod_z = -sign(rho_demand) * (2/pi) * asin(sqrt(abs(rho_demand) / rho_max));
    else
        rod_z = 0.0;
    end

    % Rod reactivity from position (inverse mapping gives rho_ext = rho_demand)
    rho_mag = rho_max * sin(pi * abs(rod_z) / 2)^2;
    rho_ext = -sign(rod_z) * rho_mag;

    % --- DIAGNOSTICS STRUCT ---
    rod_data.position = rod_z;
    rod_data.worth = rho_ext;
    rod_data.demand_reactivity = rho_demand;
    rod_data.T_avg = T_c;
    rod_data.T_avg_error = T_avg_error;

    % --- LOGGING (stateless) ---
    % Print only during significant transients to avoid console spam.
    % During steady-state (|power_error| < 3%), the controller is silent.
    if abs(power_error) > 0.03
        rho_fb = params.alpha_f * (T_f - params.T_f0_nominal) + ...
                 params.alpha_c * (T_c - params.T_c0_nominal);
        fprintf('  [LOG t=%8.1f] P=%.3f, P_dem=%.3f, P_err=%+.3f | ', ...
                t, P_norm, P_demand, power_error);
        fprintf('T_c=%6.1f, T_ref=%6.1f, T_err=%+6.1f | ', ...
                T_c, T_avg_ref, T_avg_error);
        fprintf('rod_z=%+.3f, rho_ext=%+.5f, rho_fb=%+.5f\n', ...
                rod_z, rho_ext, rho_fb);
    end

%% ========================================================================
% SCENARIOS A & B: SIMPLE RAMP PROFILE
%% ========================================================================
else
    if scenario == 1
        % Scenario A: Long-term steady-state baseline at 100% power.
        % The temperate climate scenario demonstrates stable nominal
        % operation over 24 hours. No reactivity transient.
        rho_ext = 0;
    else
        % Scenario B: Short reactivity insertion transient (hot arid).
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

end
