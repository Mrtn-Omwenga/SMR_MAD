function dydt = SMR_ODEs(t, y, params, scenario)

% 19 states: P_top, P_bottom, C_top(6), C_bottom(6), I, X, T_f, T_c, T_condenser
dydt = zeros(19,1);

% ========== UNPACK STATES ==========
P_top = y(1);
P_bottom = y(2);
C_top = y(3:8);
C_bottom = y(9:14);
I_conc = y(15);
X_conc = y(16);
T_f = y(17);
T_c = y(18);
T_condenser = y(19);

P_total = P_top + P_bottom;

% Soft state limits (prevent runaway, allow small overshoot)
P_total = max(min(P_total, 2.4), 0.01);
P_top = max(min(P_top, 1.25), 0.005);
P_bottom = max(min(P_bottom, 1.25), 0.005);

% Calculate thermal power
P_actual_MW = (P_total / 2.0) * params.P_nom;
P_actual_W = P_actual_MW * 1e6;

% ========== SAFE PARAMETERS ==========
Sigma_f_safe = max(params.Sigma_f, 1e-6);
Sigma_a_safe = max(params.Sigma_a, 0.055);
V_core_safe = max(params.V_core, 1e-6);
lambda_X_safe = max(params.lambda_X, 1e-10);
sigma_X_safe = max(params.sigma_X, 1e-20);
lambda_I_safe = max(params.lambda_I, 1e-10);
gamma_I_safe = max(params.gamma_I, 1e-6);
gamma_X_safe = max(params.gamma_X, 1e-6);

% ========== NEUTRON FLUX ==========
energy_per_fission_J = params.G * 1e6 * 1.602e-19;
reaction_rate_factor = Sigma_f_safe * V_core_safe;
phi = P_actual_W / (energy_per_fission_J * reaction_rate_factor);
phi = max(min(phi, 1e15), 1e10);

% ========== XENON REACTIVITY (PROPER PHYSICS) ==========
rho_xenon = 0;
if params.track_xenon
    denom = lambda_X_safe + sigma_X_safe * phi;
    denom = max(denom, 1e-10);
    X_eq = ((gamma_X_safe + gamma_I_safe) * Sigma_f_safe * phi) / denom;
    X_eq = max(min(X_eq, 1e17), 1e10);

    X_diff = X_conc - X_eq;
    X_diff = max(min(X_diff, 1e16), -1e16);

    rho_xenon = -sigma_X_safe * X_diff / Sigma_a_safe;
    rho_xenon = max(min(rho_xenon, 0.001), -0.005);
end

% ========== TEMPERATURE FEEDBACK ==========
T_f_safe = max(min(T_f, 1200), 300);
T_c_safe = max(min(T_c, 400), 200);

rho_fb = params.alpha_f * (T_f_safe - params.T_f0_nominal) + ...
         params.alpha_c * (T_c_safe - params.T_c0_nominal);
rho_fb = max(min(rho_fb, 0.002), -0.005);

% ========== EXTERNAL REACTIVITY ==========
rho_ext = SMR_Reactivity(t, y, params, scenario);
rho_ext = max(min(rho_ext, 0.015), -0.015);

% ========== TOTAL REACTIVITY ==========
rho_total = rho_ext + rho_fb + rho_xenon;
rho_total = max(min(rho_total, 0.005), -0.01);

% ========== POINT KINETICS ==========
Lambda_safe = max(params.Lambda, 1e-8);
lambda_col = params.lambda_i(:);
beta_col = params.beta_i(:);

sum_lambda_C_top = sum(lambda_col .* C_top);
dP_top_dt = ((rho_total - params.beta) / Lambda_safe) * P_top + sum_lambda_C_top;

sum_lambda_C_bottom = sum(lambda_col .* C_bottom);
dP_bottom_dt = ((rho_total - params.beta) / Lambda_safe) * P_bottom + sum_lambda_C_bottom;

% Soft derivative clamping
dP_top_dt = max(min(dP_top_dt, 50), -50);
dP_bottom_dt = max(min(dP_bottom_dt, 50), -50);

% ========== DELAYED NEUTRON PRECURSORS ==========
dC_top_dt = zeros(6,1);
dC_bottom_dt = zeros(6,1);
for i = 1:6
    dC_top_dt(i) = (beta_col(i) / Lambda_safe) * P_top - lambda_col(i) * C_top(i);
    dC_bottom_dt(i) = (beta_col(i) / Lambda_safe) * P_bottom - lambda_col(i) * C_bottom(i);
    dC_top_dt(i) = max(min(dC_top_dt(i), 10), -10);
    dC_bottom_dt(i) = max(min(dC_bottom_dt(i), 10), -10);
end

% ========== XENON & IODINE DYNAMICS ==========
dI_dt = gamma_I_safe * Sigma_f_safe * phi - lambda_I_safe * I_conc;
dX_dt = gamma_X_safe * Sigma_f_safe * phi + lambda_I_safe * I_conc - ...
        lambda_X_safe * X_conc - sigma_X_safe * X_conc * phi;
dI_dt = max(min(dI_dt, 1e12), -1e12);
dX_dt = max(min(dX_dt, 1e12), -1e12);

% ========== THERMAL-HYDRAULICS ==========
h_fc_W = params.h_fc * 1e6;
m_f_safe = max(params.m_f, 1000);
m_c_safe = max(params.m_c, 1000);
c_pf_safe = max(params.c_pf, 100);
c_pc_safe = max(params.c_pc, 1000);

% Fuel temperature dynamics
dT_f_dt = (P_actual_W - h_fc_W * max(0, T_f - T_c)) / (m_f_safe * c_pf_safe);
dT_f_dt = max(min(dT_f_dt, 200), -200);

% Steam generator heat transfer
Q_steam_W = params.UA_steam_gen * max(0, T_c - params.T_saturation_nominal);
Q_steam_W = min(Q_steam_W, P_actual_W);
Q_steam_W = max(Q_steam_W, 0);

% Coolant temperature dynamics
dT_c_dt = (h_fc_W * max(0, T_f - T_c) - Q_steam_W) / (m_c_safe * c_pc_safe);
dT_c_dt = max(min(dT_c_dt, 100), -100);

% ========== CONDENSER DYNAMICS ==========
% Net electric efficiency derates linearly with ambient temperature above
% 20°C design point. Turbine factor further penalizes high back-pressure
% (low condenser vacuum) via steam enthalpy drop.
efficiency_base = params.efficiency_ref - params.efficiency_derate * max(0, params.T_amb - 20);
efficiency_base = max(0.25, min(0.35, efficiency_base));

P_cond_bar = sat_pressure(T_condenser);
h_inlet = 2780;
h_outlet = steam_enthalpy(P_cond_bar);
delta_h = h_inlet - h_outlet;
delta_h_nom = 680;
turbine_factor = max(0.5, min(1.0, delta_h / delta_h_nom));

efficiency_effective = efficiency_base * turbine_factor;

Q_to_condenser_W = Q_steam_W * (1 - efficiency_effective);
Q_to_condenser_W = max(Q_to_condenser_W, 0);

mC_condenser = params.m_condenser * params.c_p_condenser;

% Cooling system dynamics
if strcmp(params.cooling_mode, 'once-through')
    c_pw = 4180;
    m_dot_cw = max(params.m_dot_cw, 100);

    dT_cw = Q_to_condenser_W / (m_dot_cw * c_pw);
    T_condenser_target = params.T_cw_in + dT_cw;
    T_condenser_target = max(T_condenser_target, params.T_cw_in + 2);
    T_condenser_target = min(T_condenser_target, params.T_cw_in + 15);

    tau = 30;
    dT_condenser_dt = (T_condenser_target - T_condenser) / tau;

elseif strcmp(params.cooling_mode, 'wet')
    T_wb = params.T_wb;

    if T_wb < 15
        eta_wet = params.cooling_tower_base_eff;
    else
        eta_wet = params.cooling_tower_base_eff - params.cooling_tower_derate * (T_wb - 15);
        eta_wet = max(eta_wet, 0.70);
    end

    approach = 12;
    T_condenser_target = T_wb + approach;
    tau = 45;
    dT_condenser_dt = (T_condenser_target - T_condenser) / tau;

elseif strcmp(params.cooling_mode, 'dry')
    if T_condenser > params.T_amb
        m_dot_air_nom = max(params.m_dot_air_nom * params.air_density_ratio, 100);
        c_p_air = params.c_p_air;

        if params.T_amb > 35
            fan_speed = max(0.9, min(1.5, (T_condenser - params.T_amb) / 12));
        else
            fan_speed = max(0.6, min(1.2, (T_condenser - params.T_amb) / 20));
        end

        fan_power_MW = params.fan_power_nom_MW * (fan_speed^3);
        fan_power_MW = max(0, min(8.0, fan_power_MW));

        m_dot_air = m_dot_air_nom * fan_speed;

        effectiveness = params.dry_cooling_effectiveness * (1 - exp(-fan_speed * 0.8));
        effectiveness = max(0.5, min(0.75, effectiveness));

        Q_cooling_capacity_W = effectiveness * m_dot_air * c_p_air * (T_condenser - params.T_amb);

        if Q_cooling_capacity_W >= Q_to_condenser_W
            T_condenser_ss = params.T_amb + Q_to_condenser_W / ...
                             (effectiveness * m_dot_air * c_p_air);
            T_condenser_ss = max(T_condenser_ss, params.T_amb + 5);
            dT_condenser_dt = (T_condenser_ss - T_condenser) / params.tau_condenser;
        else
            dT_condenser_dt = (Q_to_condenser_W - Q_cooling_capacity_W) / mC_condenser;
            dT_condenser_dt = min(dT_condenser_dt, 0.5);
        end

    else
        T_condenser_target = params.T_condenser_target;
        dT_condenser_dt = (T_condenser_target - T_condenser) / 30;
    end
else
    T_condenser_target = 35;
    dT_condenser_dt = (T_condenser_target - T_condenser) / 30;
end

dT_condenser_dt = max(min(dT_condenser_dt, 1.0), -1.0);

% ========== ASSEMBLE OUTPUT ==========
dydt(1) = dP_top_dt;
dydt(2) = dP_bottom_dt;
dydt(3:8) = dC_top_dt;
dydt(9:14) = dC_bottom_dt;
dydt(15) = dI_dt;
dydt(16) = dX_dt;
dydt(17) = dT_f_dt;
dydt(18) = dT_c_dt;
dydt(19) = dT_condenser_dt;

end

% ========== HELPER FUNCTIONS ==========
% Antoine equation for water saturation pressure.
% Valid 1–100°C. Returns pressure in bar for condenser temperature
% range (35–65°C). Used to compute turbine enthalpy drop.
function P_sat = sat_pressure(T)
    if T <= 100
        log10_P = 8.07131 - 1730.63 / (233.426 + T);
        P_mmHg = 10^log10_P;
        P_sat = P_mmHg * 0.00133322;
    else
        P_sat = 1.013 * exp((T - 100) / 45);
    end
    P_sat = max(P_sat, 0.023);
end

% Linear interpolation of steam enthalpy vs. condenser pressure.
% Tabulated from steam tables at saturated conditions. The enthalpy
% drop (h_inlet – h_outlet) drives the turbine power factor.
function h = steam_enthalpy(P_bar)
    pressure_points = [0.023, 0.05, 0.1, 0.2, 0.3, 0.5, 1.0];
    enthalpy_points = [2000, 2080, 2100, 2200, 2250, 2320, 2450];

    if P_bar <= pressure_points(1)
        h = enthalpy_points(1);
    elseif P_bar >= pressure_points(end)
        h = enthalpy_points(end);
    else
        h = interp1(pressure_points, enthalpy_points, P_bar, 'linear');
    end
end