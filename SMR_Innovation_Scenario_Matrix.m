% SMR_Innovation_Scenario_Matrix.m
% Runs each scenario with individual innovations toggled on/off to show
% which innovations matter in which environment.
%
% Cases per scenario:
%   1. Baseline (no innovations, base dry cooling effectiveness only)
%   2. +M-Cycle only
%   3. +TIAC only
%   4. +Desiccant only
%   5. +PCM only
%   6. All innovations (full MAD)
%
% Output: printed matrix and bar chart.

clear; clc; close all;

fprintf('\n=============================================================\n');
fprintf('INNOVATION SCENARIO MATRIX\n');
fprintf('=============================================================\n');

params_base = SMR_Parameters_MAD();

% Scenario definitions
scenarios = struct();
scenarios(1).name = 'A';
scenarios(1).label = 'Mt. Kenya highlands';
scenarios(1).T_amb = 20;
scenarios(1).T_wb = 15;
scenarios(1).humidity = 0.80;
scenarios(1).altitude = 1800;
scenarios(1).t_end = 86400;
scenarios(1).T_condenser_initial = 35;
scenarios(1).demand_factor = 1.0;

scenarios(2).name = 'B';
scenarios(2).label = 'Hot arid';
scenarios(2).T_amb = 45;
scenarios(2).T_wb = 22;
scenarios(2).humidity = 0.20;
scenarios(2).altitude = 400;
scenarios(2).t_end = 2000;
scenarios(2).T_condenser_initial = 55;
scenarios(2).demand_factor = 1.0;

scenarios(3).name = 'C';
scenarios(3).label = 'Coastal/transitional';
scenarios(3).T_amb = 28;
scenarios(3).T_wb = 24;
scenarios(3).humidity = 0.85;
scenarios(3).altitude = 50;
scenarios(3).t_end = 86400;
scenarios(3).T_condenser_initial = 55;
scenarios(3).demand_factor = 0.8;  % Scenario C load-following

cases = {
    'Baseline (no inno.)',      struct('maisotsenko', false, 'tiac', false, 'desiccant', false, 'pcm', false, 'eff_base', 0.70);
    '+M-Cycle only',            struct('maisotsenko', true,  'tiac', false, 'desiccant', false, 'pcm', false, 'eff_base', 0.70);
    '+TIAC only',               struct('maisotsenko', false, 'tiac', true,  'desiccant', false, 'pcm', false, 'eff_base', 0.70);
    '+Desiccant only',          struct('maisotsenko', false, 'tiac', false, 'desiccant', true,  'pcm', false, 'eff_base', 0.70);
    '+PCM only',                struct('maisotsenko', false, 'tiac', false, 'desiccant', false, 'pcm', true,  'eff_base', 0.70);
    'All innovations (MAD)',    struct('maisotsenko', true,  'tiac', true,  'desiccant', true,  'pcm', true,  'eff_base', 0.78);
};

n_scenarios = length(scenarios);
n_cases = length(cases);

% Results matrices
net_MWe = zeros(n_scenarios, n_cases);
T_cond = zeros(n_scenarios, n_cases);
turbine_factor = zeros(n_scenarios, n_cases);

% Helper functions
calc_phi = @(P_total, params) (P_total/2.0 * params.P_nom * 1e6) / ...
    (params.G * 1e6 * 1.602e-19 * params.Sigma_f * params.V_core);

calc_turbine_factor = @(T_cond) calc_tf(T_cond);

for s_idx = 1:n_scenarios
    sc = scenarios(s_idx);
    fprintf('\n--- Scenario %s: %s (T_amb=%dC, T_wb=%dC, alt=%dm) ---\n', ...
        sc.name, sc.label, sc.T_amb, sc.T_wb, sc.altitude);
    fprintf('%-24s %10s %10s %10s\n', 'Case', 'Net MWe', 'Tcond(C)', 'TurbFact');
    
    for c_idx = 1:n_cases
        case_name = cases{c_idx, 1};
        cfg = cases{c_idx, 2};
        
        params = params_base;
        params.cooling_mode = 'dry';
        params.T_amb = sc.T_amb;
        params.T_wb = sc.T_wb;
        params.humidity = sc.humidity;
        params.altitude = sc.altitude;
        params.air_density_ratio = (1 - 0.0000226 * params.altitude)^5.256;
        params.t_end = sc.t_end;
        params.T_condenser_initial = sc.T_condenser_initial;
        params.dry_cooling_effectiveness = cfg.eff_base;
        
        % Toggle innovations
        params.maisotsenko_enabled = cfg.maisotsenko;
        params.tiac_enabled = cfg.tiac;
        params.desiccant_enabled = cfg.desiccant;
        params.pcm_storage_enabled = cfg.pcm;
        params.absorption_enabled = cfg.desiccant;  % needed for desiccant benefit
        params.airflow_optimization = true;  % keep airflow optimization on for all
        
        % Scenario-specific settings
        if strcmp(sc.name, 'C')
            params.track_xenon = true;
            params.gain_scheduling_enabled = true;
            params.differential_rods_enabled = false;
        else
            params.track_xenon = false;
            params.gain_scheduling_enabled = false;
            params.differential_rods_enabled = false;
        end
        
        % Initial conditions
        if strcmp(sc.name, 'C')
            P0_steady = sc.demand_factor;
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
        
        tspan = [0 params.t_end];
        if strcmp(sc.name, 'C')
            options = odeset('RelTol', 1e-4, 'AbsTol', 1e-6, 'MaxStep', 2.0, 'Stats', 'off');
        else
            options = odeset('RelTol', 1e-6, 'AbsTol', 1e-8, 'MaxStep', 1.0);
        end
        
        % Run ODE
        try
            if strcmp(sc.name, 'C')
                [t, y] = ode15s(@(t,y) SMR_ODEs_MAD(t, y, params, 3), tspan, y0, options);
            else
                [t, y] = ode15s(@(t,y) SMR_ODEs_MAD(t, y, params, 1), tspan, y0, options);
            end
            
            % Compute final outputs
            P_total_final = y(1,end) + y(2,end);
            power_fraction = P_total_final / 2.0;
            T_cond_final = y(19,end);
            tf = calc_turbine_factor(T_cond_final);
            gross_MWe = power_fraction * params.P_elec_nom * tf;
            
            % Fan power (simplified from SMR_CalculateOutput)
            fan_power_MW = 0;
            tiac_power_MW = 0;
            T_amb_eff = params.T_amb;
            
            if params.tiac_enabled && params.T_amb > params.tiac_activation_temp
                tiac_drop = min(params.tiac_effectiveness * (params.T_amb - params.T_wb), params.tiac_temp_reduction_max);
                T_amb_eff = max(params.T_amb - tiac_drop, params.T_wb);
                tiac_power_MW = params.tiac_power_consumption_MW * power_fraction;
            end
            
            if params.maisotsenko_enabled && params.T_amb > params.m_cycle_activation_temp
                mc_drop = params.m_cycle_effectiveness * (T_amb_eff - params.T_wb);
                T_amb_eff = max(T_amb_eff - mc_drop, params.T_wb - 1.0);
            end
            
            if T_cond_final > T_amb_eff
                delta_T = T_cond_final - T_amb_eff;
                if params.T_amb > 38
                    fs = max(0.75, min(1.15, delta_T / 8));
                else
                    fs = max(0.45, min(1.1, delta_T / 15));
                end
                vsd_eff = 0.88 + 0.08 * (1 - fs);
                fan_power_MW = params.fan_power_nom_MW * (fs^3) / vsd_eff;
                if params.T_amb > 42
                    fan_power_MW = max(0, min(6.5, fan_power_MW));
                else
                    fan_power_MW = max(0, min(5.5, fan_power_MW));
                end
            end
            
            net_MWe(s_idx, c_idx) = gross_MWe - fan_power_MW - tiac_power_MW;
            T_cond(s_idx, c_idx) = T_cond_final;
            turbine_factor(s_idx, c_idx) = tf;
            
        catch ME
            fprintf('  ERROR in %s: %s\n', case_name, ME.message);
            net_MWe(s_idx, c_idx) = NaN;
            T_cond(s_idx, c_idx) = NaN;
            turbine_factor(s_idx, c_idx) = NaN;
        end
        
        fprintf('%-24s %10.1f %10.1f %10.3f\n', case_name, ...
            net_MWe(s_idx, c_idx), T_cond(s_idx, c_idx), turbine_factor(s_idx, c_idx));
    end
end

% Print summary matrix
fprintf('\n=============================================================\n');
fprintf('NET OUTPUT MATRIX (MWe)\n');
fprintf('=============================================================\n');
fprintf('%-24s', 'Case');
for s_idx = 1:n_scenarios
    fprintf(' %10s', scenarios(s_idx).name);
end
fprintf('\n');
for c_idx = 1:n_cases
    fprintf('%-24s', cases{c_idx, 1});
    for s_idx = 1:n_scenarios
        fprintf(' %10.1f', net_MWe(s_idx, c_idx));
    end
    fprintf('\n');
end

% Figure: grouped bar chart
figure('Position', [100 100 1000 600]);
b = bar(net_MWe', 'BarWidth', 0.8);
colors = lines(n_cases);
for k = 1:n_cases
    b(k).FaceColor = colors(k, :);
end
set(gca, 'XTickLabel', {scenarios.name}, 'FontSize', 11);
ylabel('Net Electrical Output (MWe)', 'FontSize', 12, 'FontWeight', 'bold');
title('Innovation Effectiveness by Scenario', 'FontSize', 13, 'FontWeight', 'bold');
legend(cases(:,1), 'Location', 'bestoutside', 'FontSize', 9);
grid on; box on;
ylim([0 max(max(net_MWe))*1.2]);

% Add value labels
for s_idx = 1:n_scenarios
    for c_idx = 1:n_cases
        if ~isnan(net_MWe(s_idx, c_idx))
            text(s_idx + (c_idx - (n_cases+1)/2)*0.1, net_MWe(s_idx, c_idx) + 1, ...
                sprintf('%.1f', net_MWe(s_idx, c_idx)), ...
                'HorizontalAlignment', 'center', 'FontSize', 7);
        end
    end
end

saveas(gcf, 'fig_innovation_scenario_matrix.png');
fprintf('\nPlot saved: fig_innovation_scenario_matrix.png\n');

% Save numeric results
save('innovation_matrix_results.mat', 'net_MWe', 'T_cond', 'turbine_factor', 'scenarios', 'cases');
fprintf('Results saved: innovation_matrix_results.mat\n');

end

function tf = calc_tf(T_cond)
    if T_cond <= 100
        log10_P = 8.07131 - 1730.63 / (233.426 + T_cond);
        P_mmHg = 10^log10_P;
        P_cond_bar = P_mmHg * 0.00133322;
    else
        P_cond_bar = 1.013 * exp((T_cond - 100) / 45);
    end
    P_cond_bar = max(P_cond_bar, 0.023);
    pressure_points = [0.023, 0.05, 0.08, 0.10, 0.12, 0.15, 0.18, 0.20, 0.25, 0.30, 0.35, 0.40, 0.50, 0.60, 0.80, 1.0];
    enthalpy_points = [2000, 2080, 2090, 2100, 2120, 2140, 2160, 2200, 2220, 2250, 2280, 2300, 2320, 2380, 2420, 2450];
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
    tf = max(0.5, min(1.0, delta_h / delta_h_nom));
end
