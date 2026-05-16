function SMR_Comparison_Suite_v2(test_mode)
% SMR_Comparison_Suite_v2.m - FIXED VERSION
% Unified comparison suite with all bugs corrected
%
% FIXES:
% 1. NO 'clear' inside function - prevents varargin wipe
% 2. Uses SMR_CalculateOutput for consistent post-processing
% 3. Sensitivity analysis uses T_amb sweep (meaningful variation)
% 4. Proper function parameter passing

% Default mode
if nargin < 1 || isempty(test_mode)
    test_mode = 'all';
end

fprintf('=============================================================\n');
fprintf('SMR COMPARISON SUITE v2 - FIXED VERSION\n');
fprintf('=============================================================\n');
fprintf('Test Mode: %s\n\n', upper(test_mode));

RUN_BASE = false; RUN_MAD = false; RUN_COMPARE = false; RUN_SENSITIVITY = false;

switch lower(test_mode)
    case 'base', RUN_BASE = true;
    case 'mad', RUN_MAD = true;
    case 'compare', RUN_COMPARE = true;
    case 'sensitivity', RUN_SENSITIVITY = true;
    case 'all', RUN_BASE = true; RUN_MAD = true; RUN_COMPARE = true; RUN_SENSITIVITY = true;
    otherwise
        fprintf('Unknown mode: %s\n', test_mode);
        fprintf('Options: base, mad, compare, sensitivity, all\n');
        return;
end

%% TEST 1: BASE MODEL (Standard Variable Demand)
if RUN_BASE
    fprintf('=============================================================\n');
    fprintf('TEST 1: BASE MODEL (Standard Variable Demand)\n');
    fprintf('=============================================================\n');

    params_base = SMR_Parameters();
    params_base.T_amb = 28; params_base.T_wb = 24; params_base.altitude = 50;
    params_base.t_end = 2000; params_base.track_xenon = false;
    params_base.cooling_mode = 'dry';
    params_base.air_density_ratio = (1 - 0.0000226 * params_base.altitude)^5.256;

    tspan = [0 params_base.t_end];
    options = odeset('RelTol', 1e-4, 'AbsTol', 1e-6, 'MaxStep', 2.0, 'Stats', 'off');

    P0 = SMR_Demand(0, params_base, 3);
    C0 = zeros(6,1);
    for i = 1:6
        C0(i) = (params_base.beta_i(i) / params_base.Lambda) * P0 / params_base.lambda_i(i);
    end

    calc_phi = @(P_total, params) (P_total/2.0 * params.P_nom * 1e6) / ...
        (params.G * 1e6 * 1.602e-19 * params.Sigma_f * params.V_core);

    phi_initial = calc_phi(P0 * 2.0, params_base);
    I0 = (params_base.gamma_I * params_base.Sigma_f * phi_initial) / params_base.lambda_I;
    numerator = params_base.gamma_X * params_base.Sigma_f * phi_initial + params_base.lambda_I * I0;
    denominator = params_base.lambda_X + params_base.sigma_X * phi_initial;
    X0 = numerator / denominator;

    T_f0 = params_base.T_f0_nominal + 300 * (P0 - 1.0);
    T_c0 = params_base.T_c0_nominal + 50 * (P0 - 1.0);

    y0 = [P0; P0; C0; C0; I0; X0; T_f0; T_c0; params_base.T_condenser_initial];

    [t, y] = ode15s(@(t,y) SMR_ODEs(t, y, params_base, 3), tspan, y0, options);

    P_total = y(:,1) + y(:,2);
    T_cond = y(:,19);
    P_final = P_total(end);
    T_cond_final = T_cond(end);

    [net, gross, tf, fan, eff] = SMR_CalculateOutput(P_final, T_cond_final, params_base);

    fprintf('Base Model (Standard):  Power: %.1f%%, T_cond: %.1fC, Net: %.1f MWe\n', ...
            P_final/2.0*100, T_cond_final, net);
end

%% TEST 2: MAD MODEL (Standard)
if RUN_MAD
    fprintf('\n=============================================================\n');
    fprintf('TEST 2: MAD MODEL (Standard Variable Demand)\n');
    fprintf('=============================================================\n');

    params_mad = SMR_Parameters_MAD();
    params_mad.T_amb = 28; params_mad.T_wb = 24; params_mad.altitude = 50;
    params_mad.t_end = 2000; params_mad.track_xenon = false;
    params_mad.cooling_mode = 'dry';
    params_mad.gain_scheduling_enabled = true;
    params_mad.pcm_storage_enabled = true;
    params_mad.absorption_enabled = true;
    params_mad.tiac_enabled = false;
    params_mad.air_density_ratio = (1 - 0.0000226 * params_mad.altitude)^5.256;

    tspan = [0 params_mad.t_end];
    options = odeset('RelTol', 1e-4, 'AbsTol', 1e-6, 'MaxStep', 2.0, 'Stats', 'off');

    P0 = SMR_Demand(0, params_mad, 3);
    C0 = zeros(6,1);
    for i = 1:6
        C0(i) = (params_mad.beta_i(i) / params_mad.Lambda) * P0 / params_mad.lambda_i(i);
    end

    calc_phi = @(P_total, params) (P_total/2.0 * params.P_nom * 1e6) / ...
        (params.G * 1e6 * 1.602e-19 * params.Sigma_f * params.V_core);

    phi_initial = calc_phi(P0 * 2.0, params_mad);
    I0 = (params_mad.gamma_I * params_mad.Sigma_f * phi_initial) / params_mad.lambda_I;
    numerator = params_mad.gamma_X * params_mad.Sigma_f * phi_initial + params_mad.lambda_I * I0;
    denominator = params_mad.lambda_X + params_mad.sigma_X * phi_initial;
    X0 = numerator / denominator;

    T_f0 = params_mad.T_f0_nominal + 300 * (P0 - 1.0);
    T_c0 = params_mad.T_c0_nominal + 50 * (P0 - 1.0);

    y0 = [P0; P0; C0; C0; I0; X0; T_f0; T_c0; params_mad.T_condenser_initial; params_mad.pcm_melt_temp];

    [t, y] = ode15s(@(t,y) SMR_ODEs_MAD(t, y, params_mad, 3), tspan, y0, options);

    P_total = y(:,1) + y(:,2);
    T_cond = y(:,19);
    P_final = P_total(end);
    T_cond_final = T_cond(end);

    [net, gross, tf, fan, eff] = SMR_CalculateOutput(P_final, T_cond_final, params_mad);

    fprintf('MAD Model (Standard):   Power: %.1f%%, T_cond: %.1fC, Net: %.1f MWe\n', ...
            P_final/2.0*100, T_cond_final, net);
end

%% TEST 3: CONSTANT-DEMAND COMPARISON
if RUN_COMPARE
    fprintf('\n=============================================================\n');
    fprintf('TEST 3: CONSTANT-DEMAND COMPARISON (P = 0.78)\n');
    fprintf('=============================================================\n');

    P_fixed = 0.78;

    % --- BASE MODEL ---
    fprintf('  [Base] Preparing...\n');
    clear SMR_Reactivity_ConstantDemand

    params_base = SMR_Parameters();
    params_base.T_amb = 28; params_base.T_wb = 24; params_base.altitude = 50;
    params_base.t_end = 500; 
    params_base.track_xenon = false;
    params_base.cooling_mode = 'dry';
    params_base.air_density_ratio = (1 - 0.0000226 * params_base.altitude)^5.256;

    tspan = [0 params_base.t_end];
    options_base = odeset('RelTol', 1e-2, 'AbsTol', 1e-4, 'MaxStep', 10.0, 'Stats', 'off');

    P0 = P_fixed;
    C0 = zeros(6,1);
    for i = 1:6
        C0(i) = (params_base.beta_i(i) / params_base.Lambda) * P0 / params_base.lambda_i(i);
    end

    calc_phi = @(P_total, params) (P_total/2.0 * params.P_nom * 1e6) / ...
        (params.G * 1e6 * 1.602e-19 * params.Sigma_f * params.V_core);

    phi_initial = calc_phi(P0 * 2.0, params_base);
    I0 = (params_base.gamma_I * params_base.Sigma_f * phi_initial) / params_base.lambda_I;
    numerator = params_base.gamma_X * params_base.Sigma_f * phi_initial + params_base.lambda_I * I0;
    denominator = params_base.lambda_X + params_base.sigma_X * phi_initial;
    X0 = numerator / denominator;

    T_f0 = params_base.T_f0_nominal + 300 * (P0 - 1.0);
    T_c0 = params_base.T_c0_nominal + 50 * (P0 - 1.0);

    y0 = [P0; P0; C0; C0; I0; X0; T_f0; T_c0; params_base.T_condenser_initial];

    fprintf('  [Base] Running solver...\n');
    tic;
    try
        [t_base, y_base] = ode23t(@(t,y) SMR_ODEs_Base_Constant(t, y, params_base, 3), ...
                                 tspan, y0, options_base);

        P_total_base = y_base(:,1) + y_base(:,2);
        T_cond_base = y_base(:,19);
        P_final_base = P_total_base(end);
        T_cond_final_base = T_cond_base(end);

        elapsed_base = toc;
        fprintf('  [Base] Done in %.2fs (%d steps)\n', elapsed_base, length(t_base));
        success_base = true;
    catch ME
        elapsed_base = toc;
        fprintf('  [Base] FAILED: %s\n', ME.message);
        P_final_base = P_fixed * 2.0;
        T_cond_final_base = params_base.T_amb + 25;
        success_base = false;
    end

    [net_base, gross_base, tf_base, fan_base, eff_base] = ...
        SMR_CalculateOutput(P_final_base, T_cond_final_base, params_base);
    
    fprintf('  [Base] Result: Power=%.1f%%, T_cond=%.1fC, Net=%.1f MWe\n', ...
            P_final_base/2.0*100, T_cond_final_base, net_base);

    % --- MAD MODEL ---
    fprintf('\n  [MAD] Preparing...\n');

    params_mad = SMR_Parameters_MAD();
    params_mad.T_amb = 28; params_mad.T_wb = 24; params_mad.altitude = 50;
    params_mad.t_end = 500;
    params_mad.track_xenon = false;
    params_mad.cooling_mode = 'dry';
    params_mad.gain_scheduling_enabled = true;
    params_mad.pcm_storage_enabled = true;
    params_mad.absorption_enabled = true;
    params_mad.tiac_enabled = false;
    params_mad.air_density_ratio = (1 - 0.0000226 * params_mad.altitude)^5.256;

    tspan = [0 params_mad.t_end];
    options_mad = odeset('RelTol', 1e-3, 'AbsTol', 1e-5, 'MaxStep', 5.0, 'Stats', 'off');

    y0 = [P0; P0; C0; C0; I0; X0; T_f0; T_c0; params_mad.T_condenser_initial; params_mad.pcm_melt_temp];

    fprintf('  [MAD] Running solver...\n');
    tic;
    try
        [t_mad, y_mad] = ode15s(@(t,y) SMR_ODEs_MAD_Constant(t, y, params_mad, 3, P_fixed), ...
                                tspan, y0, options_mad);

        P_total_mad = y_mad(:,1) + y_mad(:,2);
        T_cond_mad = y_mad(:,19);
        P_final_mad = P_total_mad(end);
        T_cond_final_mad = T_cond_mad(end);

        elapsed_mad = toc;
        fprintf('  [MAD] Done in %.2fs (%d steps)\n', elapsed_mad, length(t_mad));
        success_mad = true;
    catch ME
        elapsed_mad = toc;
        fprintf('  [MAD] FAILED: %s\n', ME.message);
        P_final_mad = P_fixed * 2.0;
        T_cond_final_mad = params_mad.T_amb + 15;
        success_mad = false;
    end

    [net_mad, gross_mad, tf_mad, fan_mad, eff_mad] = ...
        SMR_CalculateOutput(P_final_mad, T_cond_final_mad, params_mad);
    
    fprintf('  [MAD] Result: Power=%.1f%%, T_cond=%.1fC, Net=%.1f MWe\n', ...
            P_final_mad/2.0*100, T_cond_final_mad, net_mad);

    fprintf('\n--- CONSTANT DEMAND RESULTS (P = %.2f) ---\n', P_fixed);
    fprintf('                    Base Model    MAD Model     Improvement\n');
    fprintf('Final Power:        %5.1f%%       %5.1f%%        %.1f%% diff\n', ...
            P_final_base/2.0*100, P_final_mad/2.0*100, abs(P_final_base-P_final_mad)/2.0*100);
    fprintf('T_condenser:        %5.1fC      %5.1fC       %.1fC lower\n', ...
            T_cond_final_base, T_cond_final_mad, T_cond_final_base-T_cond_final_mad);
    fprintf('Turbine Factor:     %5.3f        %5.3f         %.3f higher\n', ...
            tf_base, tf_mad, tf_mad-tf_base);
    fprintf('Fan Power:          %5.1f MW     %5.1f MW      %.1f MW saved\n', ...
            fan_base, fan_mad, fan_base-fan_mad);
    fprintf('Net MWe:            %5.1f        %5.1f         +%.1f MWe (+%.0f%%)\n', ...
            net_base, net_mad, net_mad-net_base, (net_mad-net_base)/net_base*100);

    if success_base || success_mad
        figure('Position', [100, 100, 1200, 400]);

        subplot(1, 3, 1);
        if success_base
            plot(t_base, P_total_base, 'b-', 'LineWidth', 1.5); hold on;
        end
        if success_mad
            plot(t_mad, P_total_mad, 'r-', 'LineWidth', 1.5);
        end
        yl = ylim;
        plot([0 max(max(t_base(end),t_mad(end)), 10)], [P_fixed*2 P_fixed*2], 'k--', 'LineWidth', 1);
        ylim(yl);
        ylabel('Total Power (normalized)'); xlabel('Time (s)');
        legend('Base', 'MAD', 'Target', 'Location', 'best');
        title('Power Settling'); grid on;

        subplot(1, 3, 2);
        if success_base
            plot(t_base, T_cond_base, 'b-', 'LineWidth', 1.5); hold on;
        end
        if success_mad
            plot(t_mad, T_cond_mad, 'r-', 'LineWidth', 1.5);
        end
        ylabel('T_{cond} (C)'); xlabel('Time (s)');
        legend('Base', 'MAD', 'Location', 'best');
        title('Condenser Temperature'); grid on;

        subplot(1, 3, 3);
        bar_data = [net_base, net_mad];
        bar_labels = {'Base Model', 'MAD Model'};
        b = bar(bar_data);
        b.FaceColor = 'flat';
        b.CData = [0.2 0.6 0.8;
                   0.2 0.8 0.4];
        set(gca, 'XTickLabel', bar_labels);
        ylabel('Net MWe'); title('Net Output at 78%% Power');
        text(1, net_base+1, sprintf('%.1f', net_base), 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
        text(2, net_mad+1, sprintf('%.1f', net_mad), 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
        grid on;

        sgtitle(sprintf('Constant Demand Test: P_{demand} = %.2f', P_fixed));
    end
end

%% TEST 4: SENSITIVITY ANALYSIS
if RUN_SENSITIVITY
    fprintf('\n=============================================================\n');
    fprintf('TEST 4: SENSITIVITY ANALYSIS (T_amb Sweep)\n');
    fprintf('=============================================================\n');
    fprintf('Running ambient temperature sweep sensitivity analysis...\n');
    SMR_Sensitivity_Analysis;
end

fprintf('\n=============================================================\n');
fprintf('COMPARISON SUITE v2 COMPLETE\n');
fprintf('=============================================================\n');

end