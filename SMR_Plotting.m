function SMR_Plotting(t, y, P_demand, AO, rho_ext, rho_feedback, rho_total, ...
                      I_conc, X_conc, params, scenario)
% SMR_Plotting.m - CORRECTED for 19-state model
% Generates all figures for the simulation results

% Extract state variables (19-state model)
P_top = y(:,1);
P_bottom = y(:,2);
P_total = P_top + P_bottom;
T_fuel = y(:,17);      % Was y(:,17) - now correct for 19 states
T_coolant = y(:,18);   % Was y(:,18) - now correct for 19 states
T_condenser = y(:,19); % Was y(:,19) - now correct for 19 states

% For long simulations (Scenario C), downsample for plotting
if scenario == 3 && length(t) > 2000
    plot_idx = 1:round(length(t)/2000):length(t);
    t_plot = t(plot_idx);
    P_total_plot = P_total(plot_idx);
    P_demand_plot = P_demand(plot_idx);
    T_fuel_plot = T_fuel(plot_idx);
    T_coolant_plot = T_coolant(plot_idx);
    T_condenser_plot = T_condenser(plot_idx);
    AO_plot = AO(plot_idx);
    fprintf('  Downsampled for plotting: %d -> %d points\n', length(t), length(plot_idx));
else
    t_plot = t;
    P_total_plot = P_total;
    P_demand_plot = P_demand;
    T_fuel_plot = T_fuel;
    T_coolant_plot = T_coolant;
    T_condenser_plot = T_condenser;
    AO_plot = AO;
end

% Create figure
figure('Position', [50, 50, 1400, 900]);

% Convert time to hours for Scenario C
if scenario == 3
    t_display = t_plot / 3600;
    xlabel_str = 'Time (hours)';
else
    t_display = t_plot;
    xlabel_str = 'Time (seconds)';
end

%% Subplot 1: Reactor Power vs. Demand
subplot(2,3,1);
plot(t_display, P_total_plot, 'b-', 'LineWidth', 1.5); hold on;
if ~isempty(P_demand_plot)
    plot(t_display, P_demand_plot * 2.0, 'r--', 'LineWidth', 1);  % Scale demand to match P_total
end
xlabel(xlabel_str);
ylabel('Total Power (normalized)');
title('Reactor Power vs. Grid Demand');
legend('Actual Power', 'Demand (scaled)', 'Location', 'best');
grid on;
ylim([0.5 2.2]);
yline(2.0, 'k--', 'Nominal (100%)');

%% Subplot 2: Temperatures
subplot(2,3,2);
plot(t_display, T_fuel_plot, 'r-', 'LineWidth', 1.5); hold on;
plot(t_display, T_coolant_plot, 'b-', 'LineWidth', 1.5);
plot(t_display, T_condenser_plot, 'g-', 'LineWidth', 1);
yline(800, 'r--', 'Safety Limit (800°C)', 'LineWidth', 1);
xlabel(xlabel_str);
ylabel('Temperature (°C)');
title('Temperatures');
legend('Fuel', 'Coolant', 'Condenser', 'Location', 'best');
grid on;

%% Subplot 3: Axial Offset
subplot(2,3,3);
plot(t_display, AO_plot, 'g-', 'LineWidth', 1.5);
xlabel(xlabel_str);
ylabel('Axial Offset (%)');
title('Axial Offset (AO) - NOTE: Zero due to lumped feedback');
grid on;
yline(15, 'r--', 'Upper Limit (+15%)');
yline(-25, 'r--', 'Lower Limit (-25%)');
yline(0, 'k--');

%% Subplot 4: Reactivity Components
subplot(2,3,4);
if exist('rho_ext', 'var') && length(rho_ext) > 0
    if scenario == 3 && length(rho_ext) > 2000
        rho_plot_idx = 1:round(length(rho_ext)/2000):length(rho_ext);
        t_rho = t(rho_plot_idx) / (3600 * (scenario==3) + (scenario~=3));
        rho_ext_plot = rho_ext(rho_plot_idx);
        rho_total_plot = rho_total(rho_plot_idx);
    else
        t_rho = t / (3600 * (scenario==3) + (scenario~=3));
        rho_ext_plot = rho_ext;
        rho_total_plot = rho_total;
    end
    plot(t_rho, rho_ext_plot * 1e5, 'g-', 'LineWidth', 1.5); hold on;
    plot(t_rho, rho_total_plot * 1e5, 'k-', 'LineWidth', 2);
    xlabel(xlabel_str);
    ylabel('Reactivity (pcm)');
    title('Reactivity');
    legend('External Demand', 'Total', 'Location', 'best');
else
    text(0.5, 0.5, 'Reactivity data not available', 'HorizontalAlignment', 'center');
end
grid on;
yline(0, 'k--');

%% Subplot 5: Xenon and Iodine
subplot(2,3,5);
if params.track_xenon && length(X_conc) > 0
    if scenario == 3 && length(X_conc) > 2000
        xe_idx = 1:round(length(X_conc)/2000):length(X_conc);
        t_xe = t(xe_idx) / 3600;
        I_plot = I_conc(xe_idx);
        X_plot = X_conc(xe_idx);
    else
        t_xe = t / (3600 * (scenario==3) + (scenario~=3));
        I_plot = I_conc;
        X_plot = X_conc;
    end
    
    yyaxis left;
    plot(t_xe, I_plot / 1e16, 'b-', 'LineWidth', 1.5);
    ylabel('Iodine-135 (×10^{16} atoms/cm^3)');
    yyaxis right;
    plot(t_xe, X_plot / 1e16, 'r-', 'LineWidth', 1.5);
    ylabel('Xenon-135 (×10^{16} atoms/cm^3)');
    xlabel(xlabel_str);
    title('Xenon and Iodine Dynamics');
    legend('I-135', 'Xe-135', 'Location', 'best');
    grid on;
else
    % Phase plane: Power vs. Fuel Temperature
    if scenario == 3 && length(P_total) > 2000
        pp_idx = 1:round(length(P_total)/2000):length(P_total);
        P_pp = P_total(pp_idx);
        T_pp = T_fuel(pp_idx);
    else
        P_pp = P_total;
        T_pp = T_fuel;
    end
    plot(P_pp, T_pp, 'b-', 'LineWidth', 1);
    xlabel('Total Power (normalized)');
    ylabel('Fuel Temperature (°C)');
    title('Phase Plane: Power vs. Temperature');
    grid on;
    hold on;
    plot(P_pp(1), T_pp(1), 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
    plot(P_pp(end), T_pp(end), 'gs', 'MarkerSize', 8, 'MarkerFaceColor', 'g');
    legend('Trajectory', 'Start', 'End', 'Location', 'best');
end

%% Subplot 6: Top vs. Bottom Power
subplot(2,3,6);
if scenario == 3 && length(P_top) > 2000
    tb_idx = 1:round(length(P_top)/2000):length(P_top);
    t_tb = t(tb_idx) / 3600;
    P_top_plot = P_top(tb_idx);
    P_bottom_plot = P_bottom(tb_idx);
else
    t_tb = t / (3600 * (scenario==3) + (scenario~=3));
    P_top_plot = P_top;
    P_bottom_plot = P_bottom;
end
plot(t_tb, P_top_plot, 'b-', 'LineWidth', 1.5); hold on;
plot(t_tb, P_bottom_plot, 'r-', 'LineWidth', 1.5);
xlabel(xlabel_str);
ylabel('Power (normalized)');
title('Top vs. Bottom Core Power');
legend('Top Core', 'Bottom Core', 'Location', 'best');
grid on;

% Add scenario title
if scenario == 1
    title_str = 'Scenario A (Baseline: Temperate/Water-Rich)';
elseif scenario == 2
    title_str = 'Scenario B (Hot/Arid with Dry Cooling)';
else
    title_str = 'Scenario C (Weak Grid / High VRE Load-Following)';
end
sgtitle(sprintf('SMR Simulation: %s, T_{amb} = %.0f°C, Cooling = %s', ...
                title_str, params.T_amb, params.cooling_mode));

end