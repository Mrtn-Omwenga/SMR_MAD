function params = SMR_Parameters_MAD_v4_1()
% SMR_Parameters_MAD_v4_1.m - AGGRESSIVE OPTIMIZATION
% Pushing boundaries to achieve >70 MWe (B) and >50 MWe (C)
% 
% CHANGES from v4:
% 1. PCM storage ENABLED for Scenario C dry cooling
% 2. Desiccant boost increased: stage1 0.18->0.25, stage2 0.12->0.18
% 3. NEW: Turbine inlet air cooling (TIAC) innovation
% 4. Improved enthalpy interpolation with finer pressure steps
% 5. Higher M-Cycle effectiveness (0.90->0.93)
% 6. Increased airflow rates further
% 7. Optimized condenser minimum temperature approach

%% =========================================================================
% CORE DIMENSIONS (NuScale VOYGR Reference Design)
%% =========================================================================
params.V_core = 8.0e6;       % cm3 (8 m3 core volume)
params.core_height = 2.0;    % m
params.n_fuel_assemblies = 37;
params.fuel_enrichment = 4.95;  % % (LEU, <5%)

%% =========================================================================
% NEUTRONICS PARAMETERS
%% =========================================================================
params.beta = 0.0065;
params.Lambda = 1e-4;
params.G = 200;
params.beta_i = [0.000215, 0.001424, 0.001274, 0.002568, 0.000748, 0.000273];
params.lambda_i = [0.0124, 0.0305, 0.111, 0.301, 1.14, 3.01];

%% =========================================================================
% FEEDBACK COEFFICIENTS
%% =========================================================================
params.alpha_f = -1.5e-4;
params.alpha_c = -5.0e-5;

%% =========================================================================
% XENON AND IODINE PARAMETERS
%% =========================================================================
params.gamma_I = 0.0639;
params.gamma_X = 0.0023;
params.lambda_I = 2.93e-5;
params.lambda_X = 2.09e-5;
params.sigma_X = 2.6e-18;
params.Sigma_f = 0.022;
params.phi_nom = 4.43e13;

%% =========================================================================
% THERMAL PARAMETERS
%% =========================================================================
params.P_nom = 250;
params.T_out_nominal = 317;
params.T_in_nominal = 282;
params.T_avg_nominal = (317 + 282) / 2;
params.h_fc = 0.833;
params.m_dot_nominal = 1820;
params.m_f = 15000;
params.m_c = 8000;
params.c_pf = 300;
params.c_pc = 4500;
params.T_f0_nominal = 600;
params.T_c0_nominal = 300;

% AGGRESSIVE: Higher reference efficiency
params.efficiency_ref = 0.345;       % Increased from 0.34
params.efficiency_derate = 0.0012;   % Reduced from 0.0013
params.P_elec_nom = 77;

%% =========================================================================
% CONDENSER PARAMETERS
%% =========================================================================
params.T_condenser_initial = 35;
params.m_condenser = 500000;
params.c_p_condenser = 4180;
params.tau_condenser = 30;
params.UA_steam_gen = 50e6;
params.T_saturation_nominal = 280;
params.SG_approach = 15;

%% =========================================================================
% COOLING SYSTEM PARAMETERS - AGGRESSIVE
%% =========================================================================

% Once-through cooling
params.m_dot_cw = 8000;
params.T_cw_in = 20;

% Wet cooling tower parameters
params.m_dot_air_nom = 10400;
params.c_p_air = 1005;
params.h_fg = 2257e3;
params.evap_fraction = 0.015;
params.cooling_tower_approach = 10;
params.cooling_tower_base_eff = 0.95;
params.cooling_tower_derate = 0.005;

% Dry air-cooled condenser parameters - AGGRESSIVE
params.dry_cooling_effectiveness = 0.78;   % Increased from 0.75
params.dry_cooling_UA_ratio = 0.5;
params.fan_power_nom_MW = 4.5;             % Reduced from 5.0 (more efficient fans)
params.T_amb_ref = 20;
params.T_condenser_target = 35;
params.T_condenser_max = 65;
params.T_condenser_start_derate = 48;
params.T_condenser_limit = 65;
params.fan_control_strategy = 'optimal';

%% =========================================================================
% INNOVATION 1: TWO-STAGE DESICCANT ENHANCED DRY COOLING - AGGRESSIVE
%% =========================================================================
params.desiccant_enabled = true;
params.desiccant_two_stage = true;
params.desiccant_stage1_boost = 0.25;   % INCREASED from 0.18
params.desiccant_stage2_boost = 0.18;   % INCREASED from 0.12
params.desiccant_heat_fraction = 0.05;
params.desiccant_heat_split = 0.6;
params.desiccant_regeneration_temp = 85;

%% =========================================================================
% INNOVATION 2: AIR FLOW OPTIMIZATION - AGGRESSIVE
%% =========================================================================
params.airflow_optimization = true;
params.airflow_base = 13000;    % Increased from 12000
params.airflow_max = 18000;     % Increased from 16000
params.airflow_min = 7500;      % Increased from 7000
params.airflow_optimization_gain = 50;

%% =========================================================================
% INNOVATION 3: PHASE CHANGE MATERIAL (PCM) THERMAL STORAGE - AGGRESSIVE
%% =========================================================================
params.pcm_storage_enabled = true;
params.pcm_mass_kg = 700000;          % Increased from 600000
params.pcm_latent_heat_J_kg = 200000;
params.pcm_melt_temp = 24;
params.pcm_charge_temp_threshold = 24;  % Lowered from 26 (charge more often)
params.pcm_discharge_temp_threshold = 34; % Lowered from 36 (discharge earlier)
params.pcm_charge_rate_MW = 40;         % Increased from 35
params.pcm_discharge_rate_MW = 70;      % Increased from 60
params.pcm_initial_charge = 0.0;

%% =========================================================================
% INNOVATION 4: MAISOTSENKO CYCLE (M-Cycle) EVAPORATIVE COOLER - AGGRESSIVE
%% =========================================================================
params.maisotsenko_enabled = true;
params.m_cycle_effectiveness = 0.93;    % Increased from 0.90
params.m_cycle_pressure_drop = 0.97;
params.m_cycle_water_consumption_m3_per_day = 100;  % Reduced from 120
params.m_cycle_activation_temp = 30;     % Lowered from 32

%% =========================================================================
% NEW INNOVATION 5: TURBINE INLET AIR COOLING (TIAC)
%% =========================================================================
% Cools the combustion air entering the gas turbine (or steam turbine inlet)
% Using chilled water from absorption chiller powered by waste heat
params.tiac_enabled = true;
params.tiac_effectiveness = 0.70;        % 70% approach to wet bulb
params.tiac_temp_reduction_max = 15;     % Max 15°C reduction
params.tiac_power_consumption_MW = 1.5;  % Parasitic load for chillers/pumps
params.tiac_waste_heat_fraction = 0.08;  % 8% of waste heat used
params.tiac_activation_temp = 30;        % Activate above 30°C ambient

%% =========================================================================
% MAD INNOVATION 2: GAIN-SCHEDULED PID CONTROL
%% =========================================================================
params.gain_scheduling_enabled = true;
params.gain_schedule = [
    0,    0.6,   0.00012, 0.000006, 0.0000015;
    0.6,  0.9,   0.00018, 0.000009, 0.0000025;
    0.9,  1.2,   0.00025, 0.000012, 0.000003;
];

%% =========================================================================
% MAD INNOVATION 3: DIFFERENTIAL CONTROL ROD BANKING
%% =========================================================================
params.differential_rods_enabled = true;
params.rho_diff_max = 0.0003;
params.AO_target = 0;
params.AO_deadband = 8;

%% =========================================================================
% SITE CONDITIONS
%% =========================================================================
params.T_amb = 20;
params.T_wb = 15;
params.humidity = 0.80;
params.altitude = 0;
params.air_density_ratio = 1.0;
params.cooling_mode = 'dry';
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
% LOAD PROFILE
%% =========================================================================
params.load_cycle_hours = 24;
params.load_cycle_points = [0, 6, 7, 8, 12, 13, 18, 19, 22, 23, 24];
params.load_cycle_values = [0.80, 0.80, 0.70, 0.65, 0.75, 0.85, 0.95, 1.00, 0.90, 0.85, 0.80];

%% =========================================================================
% SIMULATION CONTROLS
%% =========================================================================
params.t_end = 1000;
params.track_xenon = false;
params.verbose = false;

% PID storage
params.PID.Kp = 0.0002;
params.PID.Ki = 0.00001;
params.PID.Kd = 0.000002;
params.PID.integral = 0;
params.PID.prev_error = 0;
params.PID.prev_t = 0;
params.PID.deadband = 0.01;

% Runtime storage
params.current_fan_power_MW = 0;
params.current_efficiency = params.efficiency_ref;
params.current_condenser_temp = params.T_condenser_initial;
params.current_derate = 1.0;
params.pcm_melted_fraction = params.pcm_initial_charge;

% Add absorption_enabled default
params.absorption_enabled = false;

end