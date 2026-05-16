function Xenon_Diagnostics(params)
% Xenon_Diagnostics.m
% Calculates and displays all xenon-related parameters to verify correctness

fprintf('\n========================================\n');
fprintf('XENON PARAMETER DIAGNOSTICS\n');
fprintf('========================================\n');

%% Display all xenon parameters
fprintf('\n--- INPUT PARAMETERS ---\n');
fprintf('gamma_X (Xe fission yield)   = %.6f\n', params.gamma_X);
fprintf('gamma_I (I fission yield)    = %.6f\n', params.gamma_I);
fprintf('lambda_X (Xe decay constant) = %.6e s^-1 (half-life = %.2f hours)\n', ...
    params.lambda_X, log(2)/params.lambda_X/3600);
fprintf('lambda_I (I decay constant)  = %.6e s^-1 (half-life = %.2f hours)\n', ...
    params.lambda_I, log(2)/params.lambda_I/3600);
fprintf('sigma_X (Xe absorption)      = %.6e cm^2\n', params.sigma_X);
fprintf('Sigma_f (fission cross-section) = %.6f cm^-1\n', params.Sigma_f);
fprintf('phi_nom (nominal flux)       = %.6e n/cm^2·s\n', params.phi_nom);

%% Calculate derived quantities
fprintf('\n--- DERIVED QUANTITIES ---\n');

% Microscopic cross-section (typical value for thermal reactors)
% Sigma_f = N_U235 * sigma_f, where N_U235 is number density
% For typical PWR: Sigma_f ≈ 0.1-0.3 cm^-1
fprintf('Sigma_f is reasonable if U-235 number density ~ %.2e atoms/cm^3\n', ...
    params.Sigma_f / 580e-24);

% Equilibrium xenon at full power
phi0 = params.phi_nom;
X_eq_full = (params.gamma_X * params.Sigma_f * phi0) / (params.lambda_X + params.sigma_X * phi0);
fprintf('\nXe equilibrium at full power:\n');
fprintf('  X_eq = %.6e atoms/cm^3\n', X_eq_full);

% Check if this is physically reasonable
% Typical Xe concentration in PWR: 1-3e13 atoms/cm^3 at full power
if X_eq_full > 1e14
    fprintf('  WARNING: Xe concentration (%.2e) is higher than typical PWR range (1-3e13)\n', X_eq_full);
    fprintf('  Possible causes: Sigma_f too large, phi_nom too large, or gamma_X too large\n');
elseif X_eq_full < 1e12
    fprintf('  WARNING: Xe concentration (%.2e) is lower than typical PWR range (1-3e13)\n', X_eq_full);
else
    fprintf('  ✓ Xe concentration is within typical range\n');
end

%% Check xenon reactivity worth
fprintf('\n--- XENON REACTIVITY WORTH ---\n');

% Typical xenon reactivity at full power is about -0.02 to -0.05 Δk/k
X_typical = 2e13;
rho_xenon_typical = -params.sigma_X * (X_typical) / params.Sigma_f;
fprintf('At typical Xe = %.2e atoms/cm^3:\n', X_typical);
fprintf('  rho_xenon = -sigma_X * X / Sigma_f = %.6f\n', rho_xenon_typical);

if abs(rho_xenon_typical) < 0.001
    fprintf('  WARNING: Xenon reactivity (%.4f) is very small\n', rho_xenon_typical);
    fprintf('  Expected range: -0.02 to -0.05 for typical PWR\n');
elseif abs(rho_xenon_typical) > 0.1
    fprintf('  WARNING: Xenon reactivity (%.4f) is too large\n', rho_xenon_typical);
else
    fprintf('  ✓ Xenon reactivity is within typical range\n');
end

%% Check equilibrium condition at initial state
fprintf('\n--- INITIAL EQUILIBRIUM CHECK ---\n');

% The initial conditions should satisfy dX/dt = 0
phi0 = params.phi_nom;
P0 = 1.0;  % Normalized power

% Production terms
prod_direct = params.gamma_X * params.Sigma_f * phi0;
prod_from_I = params.lambda_I * ((params.gamma_I * params.Sigma_f * phi0) / params.lambda_I);
prod_total = prod_direct + prod_from_I;

% Loss terms
X_eq_check = (params.gamma_X * params.Sigma_f * phi0) / (params.lambda_X + params.sigma_X * phi0);
loss_decay = params.lambda_X * X_eq_check;
loss_abs = params.sigma_X * X_eq_check * phi0;

fprintf('At equilibrium:\n');
fprintf('  Production from fission: %.6e atoms/cm^3·s\n', prod_direct);
fprintf('  Production from I-135:   %.6e atoms/cm^3·s\n', prod_from_I);
fprintf('  Total production:        %.6e atoms/cm^3·s\n', prod_total);
fprintf('  Loss from decay:         %.6e atoms/cm^3·s\n', loss_decay);
fprintf('  Loss from absorption:    %.6e atoms/cm^3·s\n', loss_abs);
fprintf('  Total loss:              %.6e atoms/cm^3·s\n', loss_decay + loss_abs);

if abs(prod_total - (loss_decay + loss_abs)) / prod_total < 0.01
    fprintf('  ✓ Equilibrium condition satisfied\n');
else
    fprintf('  ✗ Equilibrium condition NOT satisfied (error = %.2f%%)\n', ...
        100 * abs(prod_total - (loss_decay + loss_abs)) / prod_total);
end

%% Check time constants
fprintf('\n--- TIME CONSTANTS ---\n');
tau_I = 1 / params.lambda_I / 3600;
tau_X = 1 / params.lambda_X / 3600;
fprintf('Iodine time constant:  %.2f hours\n', tau_I);
fprintf('Xenon time constant:   %.2f hours\n', tau_X);
fprintf('Simulation should run at least %.0f hours to see equilibrium\n', 5 * tau_X);

%% Recommended parameter ranges (from Duderstadt & Hamilton, 1976)
fprintf('\n--- REFERENCE VALUES (Duderstadt & Hamilton, 1976) ---\n');
fprintf('Parameter   | Literature Range     | Your Value\n');
fprintf('------------|---------------------|-------------\n');
fprintf('gamma_X     | 0.0023               | %.6f %s\n', params.gamma_X, ...
    iif(abs(params.gamma_X - 0.0023)/0.0023 < 0.01, '✓', '✗'));
fprintf('gamma_I     | 0.0639               | %.6f %s\n', params.gamma_I, ...
    iif(abs(params.gamma_I - 0.0639)/0.0639 < 0.01, '✓', '✗'));
fprintf('lambda_X    | 2.09e-5 s^-1         | %.6e s^-1 %s\n', params.lambda_X, ...
    iif(abs(params.lambda_X - 2.09e-5)/2.09e-5 < 0.01, '✓', '✗'));
fprintf('lambda_I    | 2.93e-5 s^-1         | %.6e s^-1 %s\n', params.lambda_I, ...
    iif(abs(params.lambda_I - 2.93e-5)/2.93e-5 < 0.01, '✓', '✗'));
fprintf('sigma_X     | 2.6e-18 cm^2         | %.6e cm^2 %s\n', params.sigma_X, ...
    iif(abs(params.sigma_X - 2.6e-18)/2.6e-18 < 0.01, '✓', '✗'));

fprintf('\n========================================\n');

end

function result = iif(condition, true_val, false_val)
    if condition
        result = true_val;
    else
        result = false_val;
    end
end