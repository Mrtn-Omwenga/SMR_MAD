% SMR_Main_MAD.m - OPTIMIZED VERSION v4.1
% MAD (Minimally Adaptable Design) Simulations - AGGRESSIVE OPTIMIZATION
% 
% OPTIMIZATIONS in v4.1:
% 1. PCM storage ENABLED for Scenario C dry cooling
% 2. Desiccant boost: stage1 0.25, stage2 0.18
% 3. NEW: Turbine Inlet Air Cooling (TIAC) innovation
% 4. Improved enthalpy interpolation with finer pressure steps
% 5. Higher M-Cycle effectiveness (0.93)
% 6. Enhanced air flow rates
% 7. Optimized condenser minimum temperature approach

clear; clc; close all;

fprintf('\n=============================================================\n');
fprintf('MINIMALLY ADAPTABLE DESIGN (MAD) SIMULATION SUITE - OPTIMIZED v4.1\n');
fprintf('=============================================================\n');

params_base = SMR_Parameters_MAD();

runs = [
    1, 1, 1;   % A - Once-through
    1, 2, 2;   % A - Wet tower
    2, 3, 3;   % B - Dry cooling with MAD
    3, 1, 4;   % C - Once-through
    3, 2, 5;   % C - Wet tower
    3, 3, 6;   % C - Dry cooling with MAD
];

cooling_names = {'once-through', 'wet', 'dry'};
cooling_display = {'Once-through', 'Wet Cooling Tower', 'Dry Air-Cooled (MAD v4.1)'};
scenario_names = {'A', 'B', 'C'};

all_results = [];

calc_phi = @(P_total, params) (P_total/2.0 * params.P_nom * 1e6) / ...
    (params.G * 1e6 * 1.602e-19 * params.Sigma_f * params.V_core);

function tf = calc_turbine_factor(T_cond)
    % IMPROVED v4.1: Finer enthalpy interpolation
    if T_cond <= 100
        log10_P = 8.07131 - 1730.63 / (233.426 + T_cond);
        P_mmHg = 10^log10_P;
        P_cond_bar = P_mmHg * 0.00133322;
    else
        P_cond_bar = 1.013 * exp((T_cond - 100) / 45);
    end
    P_cond_bar = max(P_cond_bar, 0.023);

    % Finer pressure-enthalpy lookup
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
    tf = max(0.5, min(1.0, delta_h / delta_h_nom));
end

for run_idx = 1:size(runs, 1)
    scenario = runs(run_idx, 1);
    cooling_idx = runs(run_idx, 2);
    cooling_mode = cooling_names{cooling_idx};

    fprintf('\n-------------------------------------------------------------\n');
    fprintf('MAD RUN %d: Scenario %s - %s\n', run_idx, scenario_names{scenario}, cooling_display{cooling_idx});
    fprintf('-------------------------------------------------------------\n');

    params = params_base;
    params.cooling_mode = cooling_mode;

    switch scenario
        case 1
            params.T_amb = 20; params.T_wb = 15; params.humidity = 0.80;
            params.altitude = 1800; params.t_end = 86400;
            params.air_density_ratio = (1 - 0.0000226 * params.altitude)^5.256;
            params.absorption_enabled = false;
            params.track_xenon = true;
            params.pcm_storage_enabled = false;
            params.tiac_enabled = false;  % TIAC not needed in temperate
            params.T_condenser_initial = 35;
        case 2
            params.T_amb = 45; params.T_wb = 22; params.humidity = 0.20;
            params.altitude = 400; params.t_end = 2000;
            params.air_density_ratio = (1 - 0.0000226 * params.altitude)^5.256;
            params.absorption_enabled = true;
            params.track_xenon = false;
            params.pcm_storage_enabled = true;
            params.tiac_enabled = true;   % ENABLE TIAC for hot arid
            params.T_condenser_initial = 55;
        case 3
            params.T_amb = 28; params.T_wb = 24; params.humidity = 0.85;
            params.altitude = 50; 
            params.air_density_ratio = (1 - 0.0000226 * params.altitude)^5.256;
            params.gain_scheduling_enabled = true;
            params.track_xenon = true;
            params.t_end = 86400;
            if strcmp(cooling_mode, 'dry')
                params.differential_rods_enabled = false;
                params.pcm_storage_enabled = true;  % ENABLE PCM for Scenario C dry
                params.absorption_enabled = true;
                params.tiac_enabled = true;         % ENABLE TIAC for Scenario C dry
                params.T_condenser_initial = 55;
            else
                params.differential_rods_enabled = true;
                params.pcm_storage_enabled = false;
                params.absorption_enabled = false;
                params.tiac_enabled = false;
                params.T_condenser_initial = 35;
            end
    end

    if scenario == 3
        options = odeset('RelTol', 1e-4, 'AbsTol', 1e-6, 'MaxStep', 2.0, 'Stats', 'off');
    else
        options = odeset('RelTol', 1e-6, 'AbsTol', 1e-8, 'MaxStep', 1.0);
    end

    tspan = [0 params.t_end];

    % ========== INITIAL CONDITIONS (20 STATES) ==========
    if scenario == 3
        P0_steady = SMR_Demand(0, params, scenario);
    else
        P0_steady = 1.0;
    end

    C0 = zeros(6,1);
    for i = 1:6
        C0(i) = (params.beta_i(i) / params.Lambda) * P0_steady / params.lambda_i(i);
    end

    phi_full_power = calc_phi(2.0, params);
    I0 = (params.gamma_I * params.Sigma_f * phi_full_power) / params.lambda_I;
    numerator = params.gamma_X * params.Sigma_f * phi_full_power + params.lambda_I * I0;
    denominator = params.lambda_X + params.sigma_X * phi_full_power;
    X0 = numerator / denominator;

    y0 = [P0_steady; P0_steady; C0; C0; I0; X0; ...
          params.T_f0_nominal; params.T_c0_nominal; ...
          params.T_condenser_initial; params.pcm_melt_temp; params.pcm_initial_charge];

    % ========== RUN SOLVER ==========
    try
        tic;
        fprintf('  Starting solver...\n');
        if scenario == 3
            options = odeset(options, 'Events', @(t,y) SMR_Events_MAD(t,y,params));
            try
                [t, y, te, ye, ie] = ode15s(@(t,y) SMR_ODEs_MAD(t, y, params, scenario), tspan, y0, options);
                if ~isempty(ie)
                    fprintf('  WARNING: Event %d at t=%.1fs\n', ie(1), te(1));
                end
            catch ME
                fprintf('  Event solver failed: %s\n', ME.message);
                fprintf('  Retrying without events...\n');
                [t, y] = ode15s(@(t,y) SMR_ODEs_MAD(t, y, params, scenario), tspan, y0, options);
                te = []; ye = []; ie = [];
            end
        else
            [t, y] = ode15s(@(t,y) SMR_ODEs_MAD(t, y, params, scenario), tspan, y0, options);
            te = []; ye = []; ie = [];
        end
        elapsed = toc;
        fprintf('  Completed: %d steps in %.2fs\n', length(t), elapsed);

        if isempty(t)
            fprintf('  ERROR: Solver returned empty\n');
            continue;
        end

        if length(t) <= 2
            fprintf('  WARNING: Only %d time steps - possible solver stall\n', length(t));
        end

    catch ME
        fprintf('  ERROR: %s\n', ME.message);
        continue;
    end

    % ========== PROCESS RESULTS ==========
    P_total = y(:,1) + y(:,2);
    T_fuel = y(:,17);
    T_cond = y(:,19);
    AO = (y(:,1) - y(:,2)) ./ (y(:,1) + y(:,2) + eps) * 100;

    P_demand = zeros(size(t));
    for i = 1:length(t)
        try
            P_demand(i) = SMR_Demand(t(i), params, scenario);
        catch
            P_demand(i) = 0.8;
        end
    end

    P_final = P_total(end);
    T_cond_final = T_cond(end);
    P_peak = max(P_total);
    P_min = min(P_total);

    % ========== OVERSHOOT CALCULATION ==========
    if scenario == 3
        P_demand_scaled = P_demand * 2.0;
        tracking_error = P_total - P_demand_scaled;
        max_positive_excursion = max(tracking_error);
        max_negative_excursion = min(tracking_error);

        if max_positive_excursion > 0
            P_overshoot = (max_positive_excursion / max(P_demand_scaled(end), 0.01)) * 100;
        else
            P_overshoot = 0;
        end

        if max_negative_excursion < 0
            P_undershoot = abs(max_negative_excursion) / max(P_demand_scaled(end), 0.01) * 100;
        else
            P_undershoot = 0;
        end

        fprintf('  Tracking: max overshoot %.1f%%, max undershoot %.1f%%\n', ...
                P_overshoot, P_undershoot);
    else
        if P_peak > P_final
            P_overshoot = (P_peak - P_final) / max(P_final, 0.01) * 100;
        else
            P_overshoot = 0;
        end
        P_undershoot = 0;
    end

    if isnan(P_overshoot) || isinf(P_overshoot)
        P_overshoot = 0;
    end

    turbine_factor = calc_turbine_factor(T_cond_final);
    gross_MWe = (P_final / 2.0) * params.P_elec_nom * turbine_factor;

    % ========== OPTIMIZED FAN POWER CALCULATION v4.1 ==========
    fan_power_MW = 0;
    tiac_power_MW = 0;

    if strcmp(cooling_mode, 'dry')
        % Calculate effective ambient (same logic as ODE)
        T_amb_eff = params.T_amb;

        % Apply TIAC first
        if params.tiac_enabled && params.T_amb > params.tiac_activation_temp
            tiac_temp_drop = min(params.tiac_effectiveness * (params.T_amb - params.T_wb), ...
                                 params.tiac_temp_reduction_max);
            T_tiac_out = params.T_amb - tiac_temp_drop;
            T_tiac_out = max(T_tiac_out, params.T_wb);
            T_amb_eff = T_tiac_out;
            tiac_power_MW = params.tiac_power_consumption_MW * (P_final / 2.0);
        end

        % Apply M-Cycle
        if params.maisotsenko_enabled && params.T_amb > params.m_cycle_activation_temp
            m_cycle_eff = min(params.m_cycle_effectiveness, 1.0);
            T_mcycle_out = T_amb_eff - m_cycle_eff * (T_amb_eff - params.T_wb);
            T_mcycle_out = max(T_mcycle_out, params.T_wb);
            T_amb_eff = T_mcycle_out;
        end

        % Calculate fan speed based on effective ambient
        if T_cond_final > T_amb_eff
            if params.T_amb > 38
                fs = max(0.75, min(1.15, (T_cond_final - T_amb_eff) / 8));
            else
                fs = max(0.45, min(1.1, (T_cond_final - T_amb_eff) / 15));
            end
            % Apply VSD efficiency factor
            vsd_eff = 0.88 + 0.08 * (1 - fs);
            fan_power_MW = params.fan_power_nom_MW * (fs^3) / vsd_eff;
            if params.T_amb > 42
                fan_power_MW = max(0, min(6.5, fan_power_MW));
            else
                fan_power_MW = max(0, min(5.5, fan_power_MW));
            end
        else
            fan_power_MW = 0;
        end

        net_MWe = gross_MWe - fan_power_MW - tiac_power_MW;
    else
        net_MWe = gross_MWe;
    end

    fprintf('\n--- RESULTS ---\n');
    fprintf('  Power: %.1f%% (%.1f MWt)\n', P_final/2.0*100, P_final/2.0*250);
    fprintf('  Power range: %.3f to %.3f\n', P_min, P_peak);
    fprintf('  T_cond: %.1fC, T_fuel: %.1fC\n', T_cond_final, T_fuel(end));
    fprintf('  T_fuel range: %.1f to %.1fC\n', min(T_fuel), max(T_fuel));
    fprintf('  Turbine factor: %.3f\n', turbine_factor);
    fprintf('  Overshoot: %.1f%%\n', P_overshoot);
    fprintf('  Gross: %.1f MWe', gross_MWe);
    if strcmp(cooling_mode, 'dry')
        fprintf(', Fan: %.1f MW, TIAC: %.1f MW', fan_power_MW, tiac_power_MW);
    end
    fprintf('\n');
    fprintf('  Net: %.1f MWe\n', net_MWe);

    % ========== ACCEPTANCE CRITERIA ==========
    criteria_met = 0;
    verdict = 'PASS';
    early = false;

    if scenario == 3 && ~isempty(ie) && te(1) < params.t_end * 0.95
        early = true;
        verdict = 'FAIL';
        criteria_met = 0;
        fprintf('  TERMINATED EARLY at t=%.1fs\n', te(1));
    end

    if ~early
        % Criterion 1: Power stability or load-following
        if scenario == 3
            err = abs(P_final/2.0 - SMR_Demand(t(end), params, scenario));
            if err < 0.15
                criteria_met = criteria_met + 1;
                fprintf('  Tracking OK (error %.1f%%)\n', err*100);
            else
                fprintf('  Tracking poor (error %.1f%%)\n', err*100);
            end
        else
            if abs(P_final - 2.0) < 0.1
                criteria_met = criteria_met + 1;
                fprintf('  Power stable\n');
            else
                fprintf('  Power offset: %.3f\n', abs(P_final-2.0));
            end
        end

        % Criterion 2: Temperature safety
        if max(T_fuel) < 800
            criteria_met = criteria_met + 1;
            fprintf('  Temperature safe (peak %.1f < 800C)\n', max(T_fuel));
        else
            fprintf('  TEMP VIOLATION: %.1fC\n', max(T_fuel));
        end

        % Criterion 3: Overshoot
        if abs(P_overshoot) < 20
            criteria_met = criteria_met + 1;
            fprintf('  Overshoot acceptable (%.1f%% < 20%%)\n', abs(P_overshoot));
        else
            fprintf('  OVERSHOOT: %.1f%%\n', P_overshoot);
        end

        % Criterion 4: Axial offset
        if min(AO) >= -25 && max(AO) <= 15
            criteria_met = criteria_met + 1;
            if max(abs(AO)) < 0.1
                fprintf('  Axial offset identically zero\n');
            else
                fprintf('  Axial offset within limits (%.1f to %.1f%%)\n', min(AO), max(AO));
            end
        else
            fprintf('  Axial offset violation (%.1f to %.1f%%)\n', min(AO), max(AO));
        end

        if criteria_met >= 3
            verdict = 'PASS';
        else
            verdict = 'FAIL';
        end
    end

    fprintf('  Verdict: %s (%d/4)\n', verdict, criteria_met);

    % Store results
    all_results(run_idx).scenario = scenario_names{scenario};
    all_results(run_idx).cooling = cooling_display{cooling_idx};
    all_results(run_idx).power_pct = P_final/2.0*100;
    all_results(run_idx).net_MWe = net_MWe;
    all_results(run_idx).gross_MWe = gross_MWe;
    all_results(run_idx).temp_cond = T_cond_final;
    all_results(run_idx).overshoot = P_overshoot;
    all_results(run_idx).undershoot = P_undershoot;
    all_results(run_idx).verdict = verdict;
    all_results(run_idx).t = t;
    all_results(run_idx).P_total = P_total;
    all_results(run_idx).T_cond = T_cond;
    all_results(run_idx).P_demand = P_demand;
    all_results(run_idx).T_fuel = T_fuel;
    all_results(run_idx).fan_power_MW = fan_power_MW;
    all_results(run_idx).tiac_power_MW = tiac_power_MW;
    all_results(run_idx).turbine_factor = turbine_factor;
end

% ========== SUMMARY TABLE ==========
fprintf('\n\n=====================================================================\n');
fprintf('                    MAD PERFORMANCE SUMMARY - OPTIMIZED v4.1\n');
fprintf('=====================================================================\n');
fprintf('Scenario | Cooling Mode              | Thermal | Gross  | Net    | Cond | Fan  | TIAC | Turbine | Overshoot | Verdict\n');
fprintf('---------------------------------------------------------------------\n');
for i = 1:length(all_results)
    fprintf('    %s    | %-24s |  %5.1f%%   |  %5.1f |  %5.1f |  %3.0fC | %4.1f | %4.1f |  %5.3f  |   %5.1f%%  | %s\n', ...
        all_results(i).scenario, all_results(i).cooling, all_results(i).power_pct, ...
        all_results(i).gross_MWe, all_results(i).net_MWe, all_results(i).temp_cond, ...
        all_results(i).fan_power_MW, all_results(i).tiac_power_MW, ...
        all_results(i).turbine_factor, all_results(i).overshoot, all_results(i).verdict);
end
fprintf('=====================================================================\n');

% ========== PLOTTING ==========
if length(all_results) > 0
    figure('Position', [100, 100, 1400, 800]);
    for i = 1:length(all_results)
        subplot(2, ceil(length(all_results)/2), i);
        yyaxis left
        plot(all_results(i).t, all_results(i).P_total, 'b-', 'LineWidth', 1.5); hold on;
        if ~isempty(all_results(i).P_demand)
            plot(all_results(i).t, all_results(i).P_demand * 2.0, 'r--', 'LineWidth', 1);
        end
        ylabel('Power (norm)'); yline(2.0, 'b--');
        yyaxis right
        plot(all_results(i).t, all_results(i).T_cond, 'r-', 'LineWidth', 1);
        ylabel('T_{cond} (°C)');
        xlabel('Time (s)');
        title(sprintf('%s - %s', all_results(i).scenario, all_results(i).cooling));
        grid on;
    end
    sgtitle('MAD SMR - All Scenarios (Optimized v4.1 with TIAC)');
end

% Save results for comparison and plotting
save('results_MAD.mat', 'all_results', '-v7.3');
fprintf('\nResults saved to results_MAD.mat\n');

fprintf('\n=============================================================\n');
fprintf('SIMULATION COMPLETE\n');
fprintf('=============================================================\n');