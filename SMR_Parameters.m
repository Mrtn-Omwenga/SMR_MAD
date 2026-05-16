function params = SMR_Parameters()

%% =========================================================================
% CORE DIMENSIONS (NuScale VOYGR Reference Design)
%% =========================================================================
params.V_core = 8.0e6;       % cm³ (8 m³ core volume)
params.core_height = 2.0;    % m
params.n_fuel_assemblies = 37;
params.fuel_enrichment = 4.95;  % % (LEU, <5%)

%% =========================================================================
% NEUTRONICS PARAMETERS (Duderstadt & Hamilton, 1976)
%% =========================================================================
params.beta = 0.0065;         % Total delayed neutron fraction
params.Lambda = 1e-4;         % Neutron generation time (s)
params.G = 200;               % MeV per fission

% Delayed neutron group data (6 groups)
params.beta_i = [0.000215, 0.001424, 0.001274, 0.002568, 0.000748, 0.000273];
params.lambda_i = [0.0124, 0.0305, 0.111, 0.301, 1.14, 3.01];

params.Sigma_a = 0.055;  % Macroscopic absorption cross-section (cm^-1)

%% =========================================================================
% FEEDBACK COEFFICIENTS (Kerlin & Upadhyaya, 2019)
%% =========================================================================
params.alpha_f = -1.5e-4;     % Doppler coefficient (Δk/k/°C)
params.alpha_c = -5.0e-5;     % Coolant temperature coefficient

%% =========================================================================
% XENON AND IODINE PARAMETERS (Duderstadt & Hamilton, 1976)
%% =========================================================================
params.gamma_I = 0.0639;      % Iodine-135 fission yield
params.gamma_X = 0.0023;      % Xenon-135 direct fission yield
params.lambda_I = 2.93e-5;    % I-135 decay constant (s^-1, half-life 6.57 hr)
params.lambda_X = 2.09e-5;    % Xe-135 decay constant (s^-1, half-life 9.17 hr)
params.sigma_X = 2.6e-18;     % Xe-135 absorption cross-section (cm^2)
params.Sigma_f = 0.022;       % Macroscopic fission cross-section (cm^-1)
params.phi_nom = 4.43e13;     % n/cm²/s

%% =========================================================================
% THERMAL PARAMETERS (NuScale FSER data) - CORRECTED c_pc
%% =========================================================================
params.P_nom = 250;           % MWt (thermal power per module)
params.T_out_nominal = 317;   % °C (core outlet temperature)
params.T_in_nominal = 282;    % °C (core inlet temperature)
params.T_avg_nominal = (317 + 282) / 2;  % 299.5°C
params.h_fc = 0.833;          % MW/°C
params.m_dot_nominal = 1820;  % kg/s
params.m_f = 15000;           % kg (fuel mass)
params.m_c = 8000;            % kg (coolant mass in core)
params.c_pf = 300;            % J/kg·°C
params.c_pc = 4500;           % CORRECTED: Water at 300°C, 12.4 MPa
params.T_f0_nominal = 600;    % °C
params.T_c0_nominal = 300;    % °C
params.efficiency_ref = 0.33;      % Reference thermal efficiency
params.efficiency_derate = 0.0015; % Efficiency loss per °C above 20°C
params.P_elec_nom = 77;            % MWe

%% =========================================================================
% CONDENSER PARAMETERS
%% =========================================================================
params.T_condenser_initial = 35;   % °C
params.m_condenser = 500000;       % kg
params.c_p_condenser = 4180;       % J/kg·°C
params.tau_condenser = 30;         % s
params.UA_steam_gen = 50e6;        % W/°C
params.T_saturation_nominal = 280; % °C
params.SG_approach = 15;           % °C

%% =========================================================================
% COOLING SYSTEM PARAMETERS - CORRECTED SIZING
%% =========================================================================

% Once-through cooling
params.m_dot_cw = 8000;        % kg/s
params.T_cw_in = 20;           % °C

% Wet cooling tower parameters
params.m_dot_air_nom = 8000;   % kg/s
params.c_p_air = 1005;         % J/kg·°C
params.h_fg = 2257e3;          % J/kg
params.evap_fraction = 0.015;
params.cooling_tower_approach = 10;  % °C
params.cooling_tower_base_eff = 0.95;
params.cooling_tower_derate = 0.005;

% Dry air-cooled condenser parameters - CORRECTED
params.dry_cooling_effectiveness = 0.65;
params.dry_cooling_UA_ratio = 0.5;
params.fan_power_nom_MW = 5.0;             % CORRECTED: More realistic
params.T_amb_ref = 20;
params.T_condenser_target = 35;            % °C
params.T_condenser_max = 65;               % °C
params.T_condenser_start_derate = 48;      % °C
params.T_condenser_limit = 65;             % °C
params.fan_control_strategy = 'optimal';

% CORRECTED: Air mass flow matches calculation in comment
params.m_dot_air_nom = 10400;              % CORRECTED from 8000

% For backward compatibility
params.h_ca_wet = 0.6;        % MW/°C
params.h_ca_dry = 0.24;       % MW/°C

%% =========================================================================
% SITE CONDITIONS
%% =========================================================================
params.T_amb = 20;
params.T_wb = 15;
params.humidity = 0.80;
params.altitude = 0;
params.air_density_ratio = 1.0;
params.cooling_mode = 'wet';
params.eta_cool = 1.0;

%% =========================================================================
% SEISMIC DESIGN
%% =========================================================================
params.PGA_standard = 0.25;
params.seismic_zone = 'Moderate';

%% =========================================================================
% REACTIVITY DEMAND PARAMETERS
%% =========================================================================
params.demand_magnitude = 0.00002;
params.demand_ramp_up_start = 10;
params.demand_ramp_up_end = 60;
params.demand_hold_start = 60;
params.demand_hold_end = 110;
params.demand_ramp_down_start = 110;
params.demand_ramp_down_end = 160;

%% =========================================================================
% LOAD PROFILE (Scenario C)
%% =========================================================================
params.load_cycle_hours = 24;
params.load_cycle_points = [0, 6, 7, 8, 12, 13, 18, 19, 22, 23, 24];
params.load_cycle_values = [0.80, 0.80, 0.70, 0.65, 0.75, 0.85, 0.95, 1.00, 0.90, 0.85, 0.80];

%% =========================================================================
% PID CONTROLLER PARAMETERS
%% =========================================================================
params.PID.Kp = 0.0002;
params.PID.Ki = 0.00001;
params.PID.Kd = 0.000002;
params.PID.integral = 0;
params.PID.prev_error = 0;
params.PID.prev_t = 0;
params.PID.deadband = 0.01;

%% =========================================================================
% SIMULATION CONTROLS
%% =========================================================================
params.t_end = 1000;
params.track_xenon = false;
params.verbose = false;

% Storage
params.current_fan_power_MW = 0;
params.current_efficiency = params.efficiency_ref;
params.current_condenser_temp = params.T_condenser_initial;
params.current_fan_speed = 1.0;
params.current_cooling_capacity = 0;
params.current_derate = 1.0;

end