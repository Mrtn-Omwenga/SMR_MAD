function [rho_ext, rho_xenon, rod_data] = SMR_Reactivity_MAD(t, y, params, scenario)
% SMR_Reactivity_MAD.m - CRDM + T-avg Program
%
% Stateless design for ode15s compatibility. No persistent variables.
% The MAD-specific innovations are in the cooling system (SMR_ODEs_MAD), not
% the controller. Using the same controller architecture ensures fair
% comparison between baseline and MAD.
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
        P_demand = 0.8;
    end

    % --- POWER TRACKING ERROR ---
    power_error = P_demand - P_norm;

    % --- T-AVG PROGRAM ---
    T_avg_slope = 30.0;
    T_avg_ref = params.T_avg_nominal - T_avg_slope * max(0, 1.0 - P_demand);
    T_avg_error = T_avg_ref - T_c;

    % --- FEEDFORWARD REACTIVITY ---
    if P_demand < 0.85
        rho_ff = -0.002;
    else
        rho_ff = 0.0;
    end

    % --- PROPORTIONAL CONTROL ---
    Kp = 0.020;
    rho_p = Kp * power_error;

    % --- TIME-WEIGHTED COMPENSATOR ---
    Ki = 0.00002;
    tau_i = 5000;
    rho_i = Ki * power_error * min(t, tau_i);
    rho_i = max(min(rho_i, 0.008), -0.008);

    % --- TOTAL CRDM DEMAND ---
    rho_demand = rho_ff + rho_p + rho_i;

    % Clamp to physical rod worth (sin-squared curve peak = 0.015)
    rho_max = 0.015;
    rho_demand = max(min(rho_demand, rho_max), -rho_max);

    % --- ALGEBRAIC ROD POSITION ---
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

%% ========================================================================
% SCENARIOS A & B: STEADY-STATE BASELINE
%% ========================================================================
else
    % Scenario A (temperate baseline): steady-state, no external reactivity.
    % Scenario B (hot/arid dry cooling): steady-state at reduced power due
    % to elevated condenser temperature; temperature feedback alone balances.
    rho_ext = 0;
end

end
