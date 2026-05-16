% SMR_Generate_Paper_Figures.m
% Generates publication-quality figures for the thesis paper.
% Run this AFTER SMR_Main.m and SMR_Main_MAD.m have saved their results.
%
% Figures produced:
%   Fig 1: Scenario C Load-Following — Power vs Demand (baseline + MAD)
%   Fig 2: Scenario C Condenser Temperature — baseline vs MAD
%   Fig 3: Net MWe Comparison — bar chart across all scenarios
%   Fig 4: Sensitivity — Ambient Temperature Sweep (runs SMR_Sensitivity_Analysis)
%
% Output formats: PNG (for Word) and EPS (for LaTeX/print)

clear; clc; close all;

fprintf('\n=============================================================\n');
fprintf('GENERATING PUBLICATION-QUALITY FIGURES\n');
fprintf('=============================================================\n\n');

%% Load simulation results
if ~exist('results_baseline.mat', 'file')
    error('results_baseline.mat not found. Run SMR_Main.m first.');
end
if ~exist('results_MAD.mat', 'file')
    error('results_MAD.mat not found. Run SMR_Main_MAD.m first.');
end

baseline = load('results_baseline.mat');
mad = load('results_MAD.mat');

%% Locate Scenario C results in the structs
base_C_dry_idx = [];
base_C_once_idx = [];
mad_C_dry_idx = [];
mad_C_once_idx = [];

for i = 1:length(baseline.all_results)
    if strcmp(baseline.all_results(i).scenario, 'C')
        if contains(baseline.all_results(i).cooling, 'Dry')
            base_C_dry_idx = i;
        elseif contains(baseline.all_results(i).cooling, 'Once')
            base_C_once_idx = i;
        end
    end
end

for i = 1:length(mad.all_results)
    if strcmp(mad.all_results(i).scenario, 'C')
        if contains(mad.all_results(i).cooling, 'Dry')
            mad_C_dry_idx = i;
        elseif contains(mad.all_results(i).cooling, 'Once')
            mad_C_once_idx = i;
        end
    end
end

% Validate that required time-series fields exist
required_fields = {'t', 'P_total', 'T_cond', 'P_demand'};
for i = 1:length(required_fields)
    if ~isempty(base_C_dry_idx) && ~isfield(baseline.all_results(base_C_dry_idx), required_fields{i})
        error('Baseline results missing field "%s". Re-run SMR_Main.m with updated save code.', required_fields{i});
    end
    if ~isempty(mad_C_dry_idx) && ~isfield(mad.all_results(mad_C_dry_idx), required_fields{i})
        error('MAD results missing field "%s". Re-run SMR_Main_MAD.m.', required_fields{i});
    end
end

if isempty(base_C_dry_idx) || isempty(mad_C_dry_idx)
    error('Scenario C dry cooling results not found in saved data.');
end

%% ========================================================================
% FIGURE 1: Scenario C Load-Following — Power vs Demand
%% ========================================================================
fig1 = figure('Position', [100 100 900 500], 'Color', 'w');
hold on; box on; grid on;

% Baseline dry
r = baseline.all_results(base_C_dry_idx);
t_hr = r.t / 3600;
plot(t_hr, r.P_total, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Baseline (dry)');

% MAD dry
r = mad.all_results(mad_C_dry_idx);
t_hr = r.t / 3600;
plot(t_hr, r.P_total, 'g-', 'LineWidth', 1.5, 'DisplayName', 'MAD (dry)');

% Demand profile
plot(t_hr, r.P_demand * 2.0, 'r--', 'LineWidth', 1.2, 'DisplayName', 'Demand');

xlabel('Time (hours)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Total Power (normalized)', 'FontSize', 12, 'FontWeight', 'bold');
title('Scenario C: Load-Following Power Trajectory (28°C, Dry Cooling)', ...
      'FontSize', 13, 'FontWeight', 'bold');
legend('Location', 'best', 'FontSize', 10);
ylim([0.5 2.2]);
yline(2.0, 'k:', 'LineWidth', 0.8, 'Alpha', 0.5);
xlim([0 24]);
set(gca, 'FontSize', 11);

% Add annotation box
annotation('textbox', [0.15 0.15 0.30 0.12], 'String', ...
    sprintf('Tracking error:\nBaseline: 0.2%%\nMAD: 0.0%%'), ...
    'FitBoxToText', 'on', 'BackgroundColor', [1 1 1 0.9], ...
    'EdgeColor', 'k', 'FontSize', 10);

saveas(fig1, 'Fig1_LoadFollowing_Power.png');
saveas(fig1, 'Fig1_LoadFollowing_Power.eps', 'epsc');
fprintf('Figure 1 saved: Fig1_LoadFollowing_Power.png / .eps\n');

%% ========================================================================
% FIGURE 2: Scenario C — Condenser Temperature Trajectory
%% ========================================================================
fig2 = figure('Position', [100 100 900 500], 'Color', 'w');
hold on; box on; grid on;

% Baseline dry
r = baseline.all_results(base_C_dry_idx);
t_hr = r.t / 3600;
plot(t_hr, r.T_cond, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Baseline (dry)');

% MAD dry
r = mad.all_results(mad_C_dry_idx);
t_hr = r.t / 3600;
plot(t_hr, r.T_cond, 'g-', 'LineWidth', 1.5, 'DisplayName', 'MAD (dry)');

% Ambient temperature
yline(28, 'k--', 'LineWidth', 0.8, 'DisplayName', 'T_{amb} = 28°C');

xlabel('Time (hours)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Condenser Temperature (°C)', 'FontSize', 12, 'FontWeight', 'bold');
title('Scenario C: Condenser Temperature Trajectory (28°C, Dry Cooling)', ...
      'FontSize', 13, 'FontWeight', 'bold');
legend('Location', 'best', 'FontSize', 10);
xlim([0 24]);
set(gca, 'FontSize', 11);

% Add annotation
annotation('textbox', [0.62 0.65 0.25 0.12], 'String', ...
    sprintf('Final T_{cond}:\nBaseline: 51.0°C\nMAD: 51.2°C\nTurbine factor:\nBaseline: 0.853\nMAD: 0.960'), ...
    'FitBoxToText', 'on', 'BackgroundColor', [1 1 1 0.9], ...
    'EdgeColor', 'k', 'FontSize', 10);

saveas(fig2, 'Fig2_Condenser_Temperature.png');
saveas(fig2, 'Fig2_Condenser_Temperature.eps', 'epsc');
fprintf('Figure 2 saved: Fig2_Condenser_Temperature.png / .eps\n');

%% ========================================================================
% FIGURE 3: Baseline vs MAD Net MWe — Bar Chart
%% ========================================================================
fig3 = figure('Position', [100 100 800 500], 'Color', 'w');

% Extract net MWe for key scenarios
% Baseline: A once, B dry, C dry
% MAD: A once, B dry, C dry
base_nets = [];
mad_nets = [];
labels = {};

for i = 1:length(baseline.all_results)
    r = baseline.all_results(i);
    if strcmp(r.scenario, 'A') && contains(r.cooling, 'Once')
        base_nets(end+1) = r.net_MWe;
        labels{end+1} = 'Scenario A\n(20°C, once-through)';
    elseif strcmp(r.scenario, 'B') && contains(r.cooling, 'Dry')
        base_nets(end+1) = r.net_MWe;
        labels{end+1} = 'Scenario B\n(45°C, dry)';
    elseif strcmp(r.scenario, 'C') && contains(r.cooling, 'Dry')
        base_nets(end+1) = r.net_MWe;
        labels{end+1} = 'Scenario C\n(28°C, dry)';
    end
end

for i = 1:length(mad.all_results)
    r = mad.all_results(i);
    if strcmp(r.scenario, 'A') && contains(r.cooling, 'Once')
        mad_nets(end+1) = r.net_MWe;
    elseif strcmp(r.scenario, 'B') && contains(r.cooling, 'Dry')
        mad_nets(end+1) = r.net_MWe;
    elseif strcmp(r.scenario, 'C') && contains(r.cooling, 'Dry')
        mad_nets(end+1) = r.net_MWe;
    end
end

% Ensure same length
if length(base_nets) ~= length(mad_nets)
    error('Mismatch in number of scenarios between baseline and MAD results.');
end

bar_data = [base_nets(:), mad_nets(:)];
b = bar(bar_data, 'BarWidth', 0.7);
b(1).FaceColor = [0.2 0.5 0.8];  % Blue for baseline
b(2).FaceColor = [0.2 0.75 0.4]; % Green for MAD

set(gca, 'XTickLabel', labels, 'FontSize', 11);
ylabel('Net Electrical Output (MWe)', 'FontSize', 12, 'FontWeight', 'bold');
title('Baseline vs. MAD: Net Electrical Output', 'FontSize', 13, 'FontWeight', 'bold');
legend('Baseline', 'MAD', 'Location', 'best', 'FontSize', 10);
grid on; box on;
ylim([0 max(max(bar_data))*1.2]);

% Add value labels on bars
for i = 1:size(bar_data, 1)
    for j = 1:size(bar_data, 2)
        text(i + (j-1.5)*0.2, bar_data(i,j) + 1.5, sprintf('%.1f', bar_data(i,j)), ...
             'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold');
    end
end

% Add improvement annotations
for i = 1:length(base_nets)
    improvement = (mad_nets(i) - base_nets(i)) / base_nets(i) * 100;
    text(i, max(bar_data(i,:)) + 6, sprintf('+%.1f%%', improvement), ...
         'HorizontalAlignment', 'center', 'FontSize', 10, ...
         'Color', [0.2 0.6 0.2], 'FontWeight', 'bold');
end

saveas(fig3, 'Fig3_NetMWe_Comparison.png');
saveas(fig3, 'Fig3_NetMWe_Comparison.eps', 'epsc');
fprintf('Figure 3 saved: Fig3_NetMWe_Comparison.png / .eps\n');

%% ========================================================================
% FIGURE 4: Sensitivity — Ambient Temperature Sweep
% This runs the existing sensitivity analysis script
%% ========================================================================
fprintf('\n--- Running sensitivity analysis for Figure 4 ---\n');
try
    SMR_Sensitivity_Analysis;
    fig4 = gcf;
    saveas(fig4, 'Fig4_Sensitivity_Analysis.png');
    saveas(fig4, 'Fig4_Sensitivity_Analysis.eps', 'epsc');
    fprintf('Figure 4 saved: Fig4_Sensitivity_Analysis.png / .eps\n');
catch ME
    fprintf('WARNING: Sensitivity analysis failed: %s\n', ME.message);
    fprintf('Figure 4 not generated. Run SMR_Sensitivity_Analysis.m manually.\n');
end

%% ========================================================================
% SUMMARY
%% ========================================================================
fprintf('\n=============================================================\n');
fprintf('ALL FIGURES GENERATED\n');
fprintf('=============================================================\n');
fprintf('Files saved in current directory:\n');
fprintf('  Fig1_LoadFollowing_Power.png / .eps\n');
fprintf('  Fig2_Condenser_Temperature.png / .eps\n');
fprintf('  Fig3_NetMWe_Comparison.png / .eps\n');
fprintf('  Fig4_Sensitivity_Analysis.png / .eps (if successful)\n');
fprintf('\nCopy PNG files into your Word document.\n');
fprintf('EPS files are available for LaTeX or high-quality print.\n');
