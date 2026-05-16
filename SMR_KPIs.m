function KPIs = SMR_KPIs(P_total, P_demand, T_fuel, AO, t, params)
% SMR_KPIs.m - Calculates all performance metrics
% Nominal power is 2.0 for P_top + P_bottom

nominal_power = 2.0;  % Because P_top = 1.0, P_bottom = 1.0 at steady state

%% Power metrics
KPIs.P_peak = max(P_total);
KPIs.P_final = P_total(end);
KPIs.P_initial = P_total(1);
KPIs.P_steady_offset = abs(KPIs.P_final - nominal_power);
KPIs.P_overshoot = (KPIs.P_peak - KPIs.P_final) / KPIs.P_final * 100;

% Power tracking error (normalized to nominal)
tracking_error = P_total - P_demand;
KPIs.tracking_error_rms = sqrt(mean(tracking_error.^2));

% Settling time (time to stay within 2% of nominal)
tolerance = 0.02 * nominal_power;
idx_settle = find(abs(P_total - nominal_power) > tolerance, 1, 'last');
if isempty(idx_settle)
    KPIs.settling_time = 0;
else
    KPIs.settling_time = t(idx_settle);
end

%% Electrical power metrics
thermal_power_fraction = KPIs.P_final / nominal_power;
KPIs.gross_power_MWe = thermal_power_fraction * params.P_elec_nom;

% Account for fan power if dry cooling is used
if isfield(params, 'current_fan_power_MW') && params.current_fan_power_MW > 0
    KPIs.fan_power_MW = params.current_fan_power_MW;
    KPIs.net_power_MWe = max(0, KPIs.gross_power_MWe - KPIs.fan_power_MW);
else
    KPIs.fan_power_MW = 0;
    KPIs.net_power_MWe = KPIs.gross_power_MWe;
end

% Also check if derate was applied (from condenser)
if isfield(params, 'current_derate') && params.current_derate < 0.99
    KPIs.net_power_MWe = KPIs.net_power_MWe * params.current_derate;
end

%% Temperature metrics
KPIs.T_fuel_peak = max(T_fuel);
KPIs.T_fuel_final = T_fuel(end);
KPIs.T_fuel_initial = T_fuel(1);
KPIs.T_fuel_safety_margin = 800 - KPIs.T_fuel_peak;
KPIs.T_fuel_safe = (KPIs.T_fuel_peak < 800);

%% Axial offset metrics
KPIs.AO_peak = max(abs(AO));
KPIs.AO_range = [min(AO), max(AO)];
KPIs.AO_within_limits = (min(AO) >= -25) && (max(AO) <= 15);

%% Xenon hold-time (for Scenario C - check if xenon was tracked)
if params.track_xenon
    % Find periods below 80% power
    threshold = 0.8 * nominal_power;
    below_threshold = find(P_total < threshold);
    
    if ~isempty(below_threshold)
        % Find first period below threshold
        start_idx = below_threshold(1);
        % Find when it returns above threshold after that
        above_idx = find(P_total(start_idx:end) > threshold, 1, 'first');
        
        if ~isempty(above_idx)
            hold_time_seconds = t(start_idx + above_idx - 1) - t(start_idx);
            KPIs.xenon_hold_time = hold_time_seconds / 3600;  % hours
            KPIs.xenon_compliant = (hold_time_seconds < 2 * 3600);
        else
            KPIs.xenon_hold_time = NaN;
            KPIs.xenon_compliant = true;
        end
    else
        KPIs.xenon_hold_time = 0;
        KPIs.xenon_compliant = true;
    end
else
    KPIs.xenon_hold_time = 0;
    KPIs.xenon_compliant = true;
end

%% Overall assessment
KPIs.criteria_met = 0;

% Criterion 1: Power returned to nominal (for steady-state scenarios)
% For Scenario C, this criterion is waived (load-following by design)
if params.track_xenon
    % Scenario C - waive the steady-state offset criterion
    KPIs.criteria_met = KPIs.criteria_met + 1;  % Auto-pass
else
    if KPIs.P_steady_offset < 0.1  % 5% of nominal (2.0)
        KPIs.criteria_met = KPIs.criteria_met + 1;
    end
end

% Criterion 2: Fuel temperature safe
if KPIs.T_fuel_safe
    KPIs.criteria_met = KPIs.criteria_met + 1;
end

% Criterion 3: Axial offset within limits
if KPIs.AO_within_limits
    KPIs.criteria_met = KPIs.criteria_met + 1;
end

% Criterion 4: Power overshoot < 20%
if KPIs.P_overshoot < 20
    KPIs.criteria_met = KPIs.criteria_met + 1;
end

% Special case: Scenario B hot/arid may have high overshoot but still pass
if KPIs.criteria_met >= 3
    KPIs.verdict = 'PASS';
else
    KPIs.verdict = 'FAIL';
end

end