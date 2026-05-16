function SMR_ResultsSummary(KPIs, params, scenario)
% SMR_ResultsSummary.m
% Prints a formatted summary of simulation results

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════════╗\n');
fprintf('║                    SMR SIMULATION RESULTS                        ║\n');
fprintf('╠══════════════════════════════════════════════════════════════════╣\n');

switch scenario
    case 1
        fprintf('║ Scenario A: Temperate/Water-Rich (Baseline)                  ║\n');
    case 2
        fprintf('║ Scenario B: Hot/Arid (Dry Cooling)                            ║\n');
    case 3
        fprintf('║ Scenario C: Weak Grid / High VRE (Load-following)             ║\n');
end

fprintf('╠══════════════════════════════════════════════════════════════════╣\n');
fprintf('║ Cooling Mode: %-40s ║\n', params.cooling_mode);
fprintf('║ Ambient Temperature: %-34d°C ║\n', params.T_amb);
fprintf('╠══════════════════════════════════════════════════════════════════╣\n');
fprintf('\n');

%% Power Metrics
fprintf('--- POWER METRICS ---\n');
fprintf('  Initial power:        %.4f (100%% nominal)\n', KPIs.P_initial);
fprintf('  Peak power:           %.4f (%.1f%% above nominal)\n', KPIs.P_peak, (KPIs.P_peak-1)*100);
fprintf('  Final power:          %.4f (%.1f%% from nominal)\n', KPIs.P_final, (KPIs.P_final-1)*100);
fprintf('  Steady-state offset:  %.4f (%.1f%%)\n', KPIs.P_steady_offset, KPIs.P_steady_offset*100);
fprintf('  Power overshoot:      %.1f%%\n', KPIs.P_overshoot);
fprintf('  Tracking error (RMS): %.4f\n', KPIs.tracking_error_rms);
fprintf('  Settling time:        %.1f s\n', KPIs.settling_time);

%% Temperature Metrics
fprintf('\n--- TEMPERATURE METRICS ---\n');
fprintf('  Initial fuel temp:    %.1f°C\n', KPIs.T_fuel_initial);
fprintf('  Peak fuel temp:       %.1f°C\n', KPIs.T_fuel_peak);
fprintf('  Final fuel temp:      %.1f°C\n', KPIs.T_fuel_final);
fprintf('  Safety margin:        %.1f°C below 800°C\n', KPIs.T_fuel_safety_margin);

%% Axial Offset Metrics
fprintf('\n--- AXIAL OFFSET METRICS ---\n');
fprintf('  AO range:             [%.1f%%, %.1f%%]\n', KPIs.AO_range(1), KPIs.AO_range(2));
fprintf('  Peak |AO|:            %.1f%%\n', KPIs.AO_peak);
fprintf('  Within limits (±25%%?): %s\n', iif(KPIs.AO_within_limits, 'YES', 'NO'));

%% Xenon Metrics (if applicable)
if ~isnan(KPIs.xenon_hold_time)
    fprintf('\n--- XENON DYNAMICS METRICS ---\n');
    fprintf('  Hold time after ramp-down: %.1f hours\n', KPIs.xenon_hold_time);
    fprintf('  Compliant (<2 hours?):     %s\n', iif(KPIs.xenon_compliant, 'YES', 'NO'));
end

%% Stability Assessment
fprintf('\n--- STABILITY ASSESSMENT ---\n');
fprintf('  Power returned to nominal: %s\n', iif(KPIs.P_steady_offset < 0.05, '✓ YES', '✗ NO'));
fprintf('  Temperature below 800°C:   %s\n', iif(KPIs.T_fuel_safe, '✓ YES', '✗ NO'));
fprintf('  Axial offset within limits: %s\n', iif(KPIs.AO_within_limits, '✓ YES', '✗ NO'));
fprintf('  Power overshoot <20%%:      %s\n', iif(KPIs.P_overshoot < 20, '✓ YES', '✗ NO'));

fprintf('\n╔══════════════════════════════════════════════════════════════════╗\n');
fprintf('║ FINAL VERDICT: %-51s ║\n', [num2str(KPIs.criteria_met) '/4 criteria met']);
if KPIs.criteria_met >= 3
    fprintf('║ ✓ MODEL IS STABLE AND VALID FOR THIS SCENARIO                    ║\n');
else
    fprintf('║ ⚠ MODEL HAS VIOLATIONS - SEE METRICS ABOVE                       ║\n');
end
fprintf('╚══════════════════════════════════════════════════════════════════╝\n');

end

function result = iif(condition, true_val, false_val)
    if condition
        result = true_val;
    else
        result = false_val;
    end
end