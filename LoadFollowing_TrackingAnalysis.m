% LoadFollowing_TrackingAnalysis.m
% Correctly calculates load-following tracking metrics for Scenario C.
% Run this to verify your paper text matches the actual simulation results.
%
% CRITICAL: Your paper mentions "57.3% below demand" in Chapter 6.
% The actual results show 14.5% max undershoot (from results_MAD.txt).
% This script confirms the correct numbers.

clear; clc;

fprintf('============================================================\n');
fprintf('SCENARIO C LOAD-FOLLOWING TRACKING ANALYSIS\n');
fprintf('============================================================\n\n');

% Load the saved results (run SMR_Main_MAD.m first to generate results_MAD.mat)
if exist('results_MAD.mat', 'file')
    load('results_MAD.mat');
    
    % Find Scenario C dry-cooled run (run 6)
    idx = 6;  % MAD Run 6: Scenario C - Dry Air-Cooled
    
    t = all_results(idx).t;
    P_total = all_results(idx).P_total;      % Normalized total power (2.0 = 100%)
    P_demand = all_results(idx).P_demand;    % Normalized demand (1.0 = 100%)
    T_cond = all_results(idx).T_cond;
    
    % Scale demand to match P_total units (demand is per-unit, P_total is 2x per-unit)
    P_demand_scaled = P_demand * 2.0;
    
    % Tracking error
    tracking_error = P_total - P_demand_scaled;
    
    % Metrics
    max_positive_excursion = max(tracking_error);
    max_negative_excursion = min(tracking_error);
    
    % Overshoot: how much ABOVE demand
    if max_positive_excursion > 0
        % Express as % of demand at that moment (or final demand)
        [~, idx_max_pos] = max(tracking_error);
        P_overshoot_pct = (max_positive_excursion / P_demand_scaled(idx_max_pos)) * 100;
    else
        P_overshoot_pct = 0;
    end
    
    % Undershoot: how much BELOW demand
    if max_negative_excursion < 0
        [~, idx_max_neg] = min(tracking_error);
        P_undershoot_pct = abs(max_negative_excursion) / P_demand_scaled(idx_max_neg) * 100;
    else
        P_undershoot_pct = 0;
    end
    
    % Alternative: express as % of FULL NOMINAL POWER (2.0)
    P_undershoot_pct_nominal = abs(max_negative_excursion) / 2.0 * 100;
    
    % Final tracking error
    final_error = abs(P_total(end) - P_demand_scaled(end)) / P_demand_scaled(end) * 100;
    
    % RMS tracking error
    rms_error = sqrt(mean(tracking_error.^2));
    rms_error_pct_demand = rms_error / mean(P_demand_scaled) * 100;
    
    fprintf('--- ACTUAL SIMULATION METRICS ---\n');
    fprintf('Run: %s - %s\n', all_results(idx).scenario, all_results(idx).cooling);
    fprintf('Simulation duration: %.0f seconds (%.1f hours)\n', t(end), t(end)/3600);
    fprintf('\n');
    fprintf('Power range: %.3f to %.3f (%.1f%% to %.1f%% of nominal)\n', ...
        min(P_total), max(P_total), min(P_total)/2.0*100, max(P_total)/2.0*100);
    fprintf('Demand range: %.3f to %.3f (%.1f%% to %.1f%% of nominal)\n', ...
        min(P_demand_scaled), max(P_demand_scaled), min(P_demand_scaled)/2.0*100, max(P_demand_scaled)/2.0*100);
    fprintf('\n');
    fprintf('Max positive excursion:  +%.3f (+%.1f%% of demand at that time)\n', ...
        max_positive_excursion, P_overshoot_pct);
    fprintf('Max negative excursion:  %.3f (-%.1f%% of demand at that time)\n', ...
        max_negative_excursion, P_undershoot_pct);
    fprintf('Max negative excursion:  %.3f (-%.1f%% of FULL NOMINAL power)\n', ...
        max_negative_excursion, P_undershoot_pct_nominal);
    fprintf('\n');
    fprintf('Final tracking error:    %.3f (%.1f%% of final demand)\n', ...
        abs(P_total(end) - P_demand_scaled(end)), final_error);
    fprintf('RMS tracking error:      %.4f (%.1f%% of mean demand)\n', ...
        rms_error, rms_error_pct_demand);
    fprintf('\n');
    
    fprintf('--- COMPARISON WITH PAPER TEXT ---\n');
    fprintf('Paper says: "57.3%% below demand at the lowest point"\n');
    fprintf('Actual:     %.1f%% below demand at worst point (relative to demand at that time)\n', P_undershoot_pct);
    fprintf('            %.1f%% below nominal at worst point (relative to full power)\n', P_undershoot_pct_nominal);
    fprintf('\n');
    fprintf('CORRECTION NEEDED: The 57.3%% figure appears to be from an old version.\n');
    fprintf('Replace with: "Max transient undershoot of %.1f%% relative to demand"\n', P_undershoot_pct);
    fprintf('Or: "Power briefly falls to %.1f%% of nominal during the overnight trough"\n', ...
        (min(P_total)/2.0)*100);
    fprintf('\n');
    
    % Plot
    figure('Position', [50, 50, 1400, 600]);
    
    subplot(2,1,1);
    plot(t/3600, P_total/2.0*100, 'b-', 'LineWidth', 1.5); hold on;
    plot(t/3600, P_demand_scaled/2.0*100, 'r--', 'LineWidth', 1);
    ylabel('Power (% of nominal)');
    legend('Reactor Power', 'Demand', 'Location', 'best');
    title('Scenario C Load-Following: Power vs Demand');
    grid on;
    ylim([50, 110]);
    
    subplot(2,1,2);
    plot(t/3600, tracking_error/2.0*100, 'g-', 'LineWidth', 1);
    ylabel('Tracking Error (% of nominal)');
    xlabel('Time (hours)');
    title('Tracking Error = Power - Demand');
    grid on;
    
    sgtitle('Scenario C Load-Following Validation');
    saveas(gcf, 'chart_loadfollowing_tracking.png');
    fprintf('Plot saved to: chart_loadfollowing_tracking.png\n');
    
else
    fprintf('ERROR: results_MAD.mat not found.\n');
    fprintf('Please run SMR_Main_MAD.m first to generate the results file.\n');
end

fprintf('============================================================\n');
