% SMR_Innovation_Scenario_Matrix.m
% Steady-state innovation scenario matrix for MAD design.
% Computes net electrical output for each scenario with different
% innovation combinations, avoiding full ODE integration.
%
% Cases per scenario:
%   1. Baseline (no innovations, base dry cooling)
%   2. +M-Cycle only
%   3. +TIAC only
%   4. +Desiccant only
%   5. +PCM only
%   6. All innovations (MAD)

clear; clc; close all;

fprintf('\n=============================================================\n');
fprintf('INNOVATION SCENARIO MATRIX (Steady-State)\n');
fprintf('=============================================================\n');

params = SMR_Parameters_MAD();

% Scenario definitions
scenarios = struct();
scenarios(1).name = 'A';
scenarios(1).label = 'Mt. Kenya highlands';
scenarios(1).T_amb = 20;
scenarios(1).T_wb = 15;
scenarios(1).altitude = 1800;
scenarios(1).power_fraction = 1.0;

scenarios(2).name = 'B';
scenarios(2).label = 'Hot arid';
scenarios(2).T_amb = 45;
scenarios(2).T_wb = 22;
scenarios(2).altitude = 400;
scenarios(2).power_fraction = 1.0;

scenarios(3).name = 'C';
scenarios(3).label = 'Coastal/transitional';
scenarios(3).T_amb = 28;
scenarios(3).T_wb = 24;
scenarios(3).altitude = 50;
scenarios(3).power_fraction = 0.8;

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

net_MWe = zeros(n_scenarios, n_cases);
T_cond = zeros(n_scenarios, n_cases);
turbine_factor = zeros(n_scenarios, n_cases);

fprintf('%-24s %10s %10s %10s\n', 'Case', 'Net MWe', 'Tcond(C)', 'TurbFact');

for s_idx = 1:n_scenarios
    sc = scenarios(s_idx);
    fprintf('\n--- Scenario %s: %s (T_amb=%dC, T_wb=%dC, alt=%dm) ---\n', ...
        sc.name, sc.label, sc.T_amb, sc.T_wb, sc.altitude);
    
    for c_idx = 1:n_cases
        case_name = cases{c_idx, 1};
        cfg = cases{c_idx, 2};
        
        [net_MWe(s_idx, c_idx), T_cond(s_idx, c_idx), turbine_factor(s_idx, c_idx)] = ...
            evaluate_case(params, sc, cfg);
        
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

% Figure
figure('Position', [100 100 1000 600]);
colors = lines(n_cases);
ax = gca;
ax.ColorOrder = colors;
ax.NextPlot = 'replacechildren';
b = bar(net_MWe', 'BarWidth', 0.8);
set(gca, 'XTickLabel', {scenarios.name}, 'FontSize', 11);
ylabel('Net Electrical Output (MWe)', 'FontSize', 12, 'FontWeight', 'bold');
title('Innovation Effectiveness by Scenario', 'FontSize', 13, 'FontWeight', 'bold');
legend(cases(:,1), 'Location', 'bestoutside', 'FontSize', 9);
grid on; box on;
ylim([0 max(max(net_MWe))*1.15]);

% Add value labels
for s_idx = 1:n_scenarios
    for c_idx = 1:n_cases
        text(s_idx + (c_idx - (n_cases+1)/2)*0.1, net_MWe(s_idx, c_idx) + 1, ...
            sprintf('%.1f', net_MWe(s_idx, c_idx)), ...
            'HorizontalAlignment', 'center', 'FontSize', 7);
    end
end

saveas(gcf, 'fig_innovation_scenario_matrix.png');
fprintf('\nPlot saved: fig_innovation_scenario_matrix.png\n');

save('innovation_matrix_results.mat', 'net_MWe', 'T_cond', 'turbine_factor', 'scenarios', 'cases');
fprintf('Results saved: innovation_matrix_results.mat\n');

%% Local function: evaluate one case
function [net_MWe, T_cond, tf] = evaluate_case(params, sc, cfg)
    % Fixed thermal conditions
    P_thermal_MW = params.P_nom * sc.power_fraction;  % 250 MWt at full power
    T_amb = sc.T_amb;
    T_wb = sc.T_wb;
    altitude = sc.altitude;
    
    % Altitude-corrected air density
    air_density_ratio = (1 - 0.0000226 * altitude)^5.256;
    m_dot_air_nom = params.m_dot_air_nom * air_density_ratio;
    c_p_air = params.c_p_air;
    
    % Cycle efficiency at ambient
    eff_cycle = params.efficiency_ref - 0.0012 * (T_amb - 20);
    Q_reject_MW = P_thermal_MW * (1 - eff_cycle);
    
    % Effective ambient after pre-cooling innovations
    effective_ambient = T_amb;
    tiac_power_MW = 0;
    
    if cfg.tiac && T_amb > params.tiac_activation_temp
        tiac_drop = min(params.tiac_effectiveness * (T_amb - T_wb), params.tiac_temp_reduction_max);
        effective_ambient = max(T_amb - tiac_drop, T_wb);
        tiac_power_MW = params.tiac_power_consumption_MW * sc.power_fraction;
    end
    
    if cfg.maisotsenko && T_amb > params.m_cycle_activation_temp
        mc_eff = params.m_cycle_effectiveness;
        mc_drop = mc_eff * (effective_ambient - T_wb);
        effective_ambient = max(effective_ambient - mc_drop, T_wb - 1.0);
    end
    
    % Desiccant effectiveness boost (humidity-aware)
    desiccant_benefit = 0;
    if cfg.desiccant
        wb_depression = T_amb - T_wb;
        humidity_factor = max(0.3, min(1.0, 1.0 - (wb_depression - 5)/25));
        desiccant_benefit = (params.desiccant_stage1_boost + params.desiccant_stage2_boost) * humidity_factor;
    end
    
    % PCM boost (steady-state average)
    pcm_benefit = 0;
    if cfg.pcm && T_amb > params.pcm_discharge_temp_threshold
        pcm_benefit = 0.04;  % equivalent to ~0.04 effectiveness boost
    end
    
    % Total effectiveness
    effectiveness = cfg.eff_base + desiccant_benefit + pcm_benefit;
    effectiveness = max(0.4, min(0.95, effectiveness));
    
    % Solve for condenser temperature and fan speed
    % At steady state: Q_reject = epsilon * m_dot_air * cp * (T_cond - T_amb_eff)
    % Fan speed fs adjusts m_dot_air = m_dot_air_nom * fs
    % Fan power = fan_nom * fs^3 / vsd_eff
    % Optimize fs to maximize net power
    
    best_net = -inf;
    best_T_cond = NaN;
    best_tf = NaN;
    
    for fs = linspace(0.3, 1.15, 50)
        m_dot_air = m_dot_air_nom * fs;
        T_cond_test = effective_ambient + Q_reject_MW * 1e6 / (effectiveness * m_dot_air * c_p_air);
        T_cond_test = max(T_cond_test, effective_ambient + 2);
        
        if T_cond_test > 100
            continue;
        end
        
        tf_test = calc_turbine_factor(T_cond_test);
        gross_MWe = P_thermal_MW * eff_cycle * tf_test;
        
        vsd_eff = 0.88 + 0.08 * (1 - fs);
        fan_MWe = params.fan_power_nom_MW * (fs^3) / vsd_eff;
        fan_MWe = min(fan_MWe, 6.5);
        
        net_test = gross_MWe - fan_MWe - tiac_power_MW;
        
        if net_test > best_net
            best_net = net_test;
            best_T_cond = T_cond_test;
            best_tf = tf_test;
        end
    end
    
    net_MWe = best_net;
    T_cond = best_T_cond;
    tf = best_tf;
end

function tf = calc_turbine_factor(T_cond)
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
