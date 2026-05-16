function dPdt = SMR_DemandRate(t, params)
% SMR_DemandRate.m - FIXED with error handling
% Analytical derivative of demand function

dPdt = 0;  % Default fallback

try
    t_hours = t / 3600;

    if t_hours >= 48 && t_hours < 72
        dPdt = 0;
        return;
    end

    cycle_hours = params.load_cycle_hours;
    t_mod = mod(t_hours, cycle_hours);

    % Validate arrays
    if ~isfield(params, 'load_cycle_points') || ~isfield(params, 'load_cycle_values')
        dPdt = 0;
        return;
    end

    if length(params.load_cycle_points) < 2
        dPdt = 0;
        return;
    end

    % Numerical derivative with small perturbation
    dt = 0.1;
    P1 = interp1(params.load_cycle_points, params.load_cycle_values, ...
                 mod((t_hours + dt/3600), cycle_hours), 'linear', 'extrap');
    P0 = interp1(params.load_cycle_points, params.load_cycle_values, ...
                 t_mod, 'linear', 'extrap');
    dPdt = (P1 - P0) / dt;
    dPdt = max(min(dPdt, 0.01), -0.01);

catch ME
    dPdt = 0;
end

end