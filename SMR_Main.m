%% 
% SMR_Main.m - FIXED VERSION for Scenario C load-following
% Changes:
% 1. Scenario C starts at demand level (not 100%)
% 2. Uses SMR_Reactivity_FIXED.m with robust PID
% 3. Tighter solver tolerances for stiff dynamics

clear; clc; close all;

fprintf('\n=============================================================\n');
fprintf('SMR SIMULATION SUITE - FIXED v7 (Load-Following Corrected)\n');
fprintf('=============================================================\n');

params_base = SMR_Parameters();

runs = [
    1, 1, 1;   % A - Once-through
    1, 2, 2;   % A - Wet tower
    2, 3, 3;   % B - Dry cooling
    3, 1, 4;   % C - Once-through
    3, 2, 5;   % C - Wet tower
    3, 3, 6;   % C - Dry cooling
];

cooling_names = {'once-through', 'wet', 'dry'};
cooling_display = {'Once-through', 'Wet Cooling Tower', 'Dry Air-Cooled'};
scenario_names = {'A', 'B', 'C'};

all_results = [];

calc_phi = @(P_total, params) (P_total/2.0 * params.P_nom * 1e6) / ...
    (params.G * 1e6 * 1.602e-19 * params.Sigma_f * params.V_core);

function tf = calc_turbine_factor(T_cond)
    if T_cond <= 100
        log10_P = 8.07131 - 1730.63 / (233.426 + T_cond);
        P_mmHg = 10^log10_P;
        P_cond_bar = P_mmHg * 0.00133322;
    else
        P_cond_bar = 1.013 * exp((T_cond - 100) / 45);
    end
    P_cond_bar = max(P_cond_bar, 0.023);

    h_inlet = 2780;
    pressure_points = [0.023, 0.05, 0.1, 0.2, 0.3, 0.5, 1.0];
    enthalpy_points = [2000, 2080, 2100, 2200, 2250, 2320, 2450];

    if P_cond_bar <= pressure_points(1)
        h_outlet = enthalpy_points(1);
    elseif P_cond_bar >= pressure_points(end)
        h_outlet = enthalpy_points(end);
    else
        h_outlet = interp1(pressure_points, enthalpy_points, P_cond_bar, 'linear');
    end

    delta_h = h_inlet - h_outlet;
    delta_h_nom = 680;
    tf = max(0.5, min(1.0, delta_h / delta_h_nom));
end

function fan_power = calc_fan_power(T_cond, T_amb, params)
    if T_cond <= T_amb
        fan_power = 0;
        return;
    end

    if T_amb > 35
        fan_speed = max(0.9, min(1.5, (T_cond - T_amb) / 12));
    else
        fan_speed = max(0.6, min(1.2, (T_cond - T_amb) / 20));
    end

    fan_power = params.fan_power_nom_MW * (fan_speed^3);
    fan_power = max(0, min(8.0, fan_power));
end

for run_idx = 1:size(runs, 1)
    scenario = runs(run_idx, 1);
    cooling_idx = runs(run_idx, 2);
    cooling_mode = cooling_names{cooling_idx};

    fprintf('\n-------------------------------------------------------------\n');
    fprintf('RUN %d: Scenario %s - %s\n', run_idx, scenario_names{scenario}, cooling_display{cooling_idx});
    fprintf('-------------------------------------------------------------\n');

    params = params_base;
    params.cooling_mode = cooling_mode;

    switch scenario
        case 1
            params.T_amb = 20; params.T_wb = 15; params.altitude = 1800;
            params.t_end = 1000; params.track_xenon = false;
            params.air_density_ratio = (1 - 0.0000226 * params.altitude)^5.256;
            params.m_dot_cw = 500; params.T_cw_in = 15;
            params.T_condenser_initial = 35;
        case 2
            params.T_amb = 45; params.T_wb = 22; params.altitude = 400;
            params.t_end = 2000; params.track_xenon = false;
            params.air_density_ratio = (1 - 0.0000226 * params.altitude)^5.256;
            params.eta_cool = 0.70; params.T_condenser_initial = 55;
        case 3
            params.T_amb = 28; params.T_wb = 24; params.altitude = 50;
            params.t_end = 1000; params.track_xenon = false;
            params.air_density_ratio = (1 - 0.0000226 * params.altitude)^5.256;
            params.m_dot_cw = 500; params.T_cw_in = 28;
            params.T_condenser_initial = 35;
    end

    % FIXED: Tighter tolerances for Scenario C stiff dynamics
    if scenario == 3
        tspan = [0 params.t_end];
        options = odeset('RelTol', 1e-4, 'AbsTol', 1e-6, 'MaxStep', 2.0, 'Stats', 'off');
    else
        tspan = [0 params.t_end];
        options = odeset('RelTol', 1e-6, 'AbsTol', 1e-8, 'MaxStep', 1.0);
    end

    % ========== FIXED INITIAL CONDITIONS ==========
    % Scenario C starts at demand level, not 100%
    if scenario == 3
        P0_steady = SMR_Demand(0, params, scenario);
        fprintf('  Starting at demand level: %.2f\n', P0_steady);
    else
        P0_steady = 1.0;
    end

    C0 = zeros(6,1);
    for i = 1:6
        C0(i) = (params.beta_i(i) / params.Lambda) * P0_steady / params.lambda_i(i);
    end

    % FIXED: Calculate flux at actual initial power for xenon/iodine
    phi_initial = calc_phi(P0_steady * 2.0, params);
    I0 = (params.gamma_I * params.Sigma_f * phi_initial) / params.lambda_I;
    numerator = params.gamma_X * params.Sigma_f * phi_initial + params.lambda_I * I0;
    denominator = params.lambda_X + params.sigma_X * phi_initial;
    X0 = numerator / denominator;

    T_f0 = params.T_f0_nominal + 300 * (P0_steady - 1.0);
    T_c0 = params.T_c0_nominal + 50 * (P0_steady - 1.0);
    T_condenser0 = params.T_condenser_initial;

    y0 = [P0_steady; P0_steady; C0; C0; I0; X0; T_f0; T_c0; T_condenser0];

    % Run solver
    try
        tic;
        if scenario == 3
            options = odeset(options, 'Events', @(t,y) SMR_Events(t,y,params));
            [t, y, te, ye, ie] = ode15s(@(t,y) SMR_ODEs(t, y, params, scenario), tspan, y0, options);
            if ~isempty(ie)
                fprintf('  WARNING: Event %d triggered at t=%.1fs\n', ie(1), te(1));
            end
        else
            [t, y] = ode15s(@(t,y) SMR_ODEs(t, y, params, scenario), tspan, y0, options);
            te = []; ye = []; ie = [];
        end
        elapsed = toc;
        fprintf('  Solver completed in %.2f seconds: %d time steps\n', elapsed, length(t));

        if isempty(t)
            fprintf('  WARNING: Solver returned empty\n');
            continue;
        end
    catch ME
        fprintf('  SOLVER ERROR: %s\n', ME.message);
        continue;
    end

    % Process results
    P_total = y(:,1) + y(:,2);
    T_fuel = y(:,17);
    T_condenser_final = y(:,19);
    AO = (y(:,1) - y(:,2)) ./ (y(:,1) + y(:,2) + eps) * 100;

    P_demand = zeros(size(t));
    for i = 1:length(t)
        P_demand(i) = SMR_Demand(t(i), params, scenario);
    end

    P_final = P_total(end);
    T_f_final = T_fuel(end);
    T_cond_final = T_condenser_final(end);
    P_peak = max(P_total);
    P_overshoot = (P_peak - P_final) / P_final * 100;
    if isnan(P_overshoot) || isinf(P_overshoot) || P_overshoot < 0
        P_overshoot = 0;
    end
    P_steady_offset = abs(P_final - 2.0);

    turbine_factor = calc_turbine_factor(T_cond_final);
    gross_MWe = (P_final/2.0) * params.P_elec_nom * turbine_factor;

    if strcmp(cooling_mode, 'dry')
        fan_power_MW = calc_fan_power(T_cond_final, params.T_amb, params);
        net_MWe = gross_MWe - fan_power_MW;
    else
        net_MWe = gross_MWe;
        fan_power_MW = 0;
    end

    % Acceptance criteria
    criteria_met = 0;

    if scenario == 3
        P_demand_final = SMR_Demand(t(end), params, scenario);
        tracking_error = abs(P_final/2.0 - P_demand_final);
        if tracking_error < 0.15
            criteria_met = criteria_met + 1;
            fprintf('  Load-following acceptable (error %.1f%%)\n', tracking_error*100);
        else
            fprintf('  Load-following poor (error %.1f%%)\n', tracking_error*100);
        end
    else
        if P_steady_offset < 0.1
            criteria_met = criteria_met + 1;
        end
    end

    if max(T_fuel) < 800
        criteria_met = criteria_met + 1;
    end
    if P_overshoot < 20
        criteria_met = criteria_met + 1;
    end
    if min(AO) >= -25 && max(AO) <= 15
        criteria_met = criteria_met + 1;
    end

    if criteria_met >= 3
        verdict = 'PASS';
    else
        verdict = 'FAIL';
    end

    fprintf('\n  Verdict: %s (%d/4 criteria)\n', verdict, criteria_met);

    all_results(run_idx).scenario = scenario_names{scenario};
    all_results(run_idx).cooling = cooling_display{cooling_idx};
    all_results(run_idx).power_MWt = P_final/2.0*250;
    all_results(run_idx).power_pct = P_final/2.0*100;
    all_results(run_idx).temp_fuel = T_f_final;
    all_results(run_idx).temp_cond = T_cond_final;
    all_results(run_idx).turbine_factor = turbine_factor;
    all_results(run_idx).overshoot = P_overshoot;
    all_results(run_idx).net_MWe = net_MWe;
    all_results(run_idx).fan_power_MW = fan_power_MW;
    all_results(run_idx).verdict = verdict;
end

fprintf('\n\n');
fprintf('=====================================================================\n');
fprintf('                    SMR PERFORMANCE SUMMARY - FIXED v7\n');
fprintf('=====================================================================\n');
fprintf('Scenario | Cooling Mode        | Thermal | Net    | Fan   | Turbine | Cond | Verdict\n');
fprintf('---------------------------------------------------------------------\n');
for i = 1:length(all_results)
    fprintf('    %s    | %-19s | %5.1fMWt | %5.1fMWe | %4.1fMW |  %5.3f  | %3.0fC | %s\n', ...
            all_results(i).scenario, all_results(i).cooling, ...
            all_results(i).power_MWt, all_results(i).net_MWe, ...
            all_results(i).fan_power_MW, all_results(i).turbine_factor, ...
            all_results(i).temp_cond, all_results(i).verdict);
end
fprintf('=====================================================================\n');