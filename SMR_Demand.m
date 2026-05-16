function P_demand = SMR_Demand(t, params, scenario)
% SMR_Demand.m - FIXED with error handling
% Calculates the power demand setpoint at time t

P_demand = 1.0;  % Default fallback

try
    if scenario == 3
        % Scenario C: 72-hour load profile based on Kenyan grid data
        t_hours = t / 3600;  % Convert seconds to hours

        % Handle 48-72 hour reduced baseload period FIRST
        if t_hours >= 48 && t_hours < 72
            P_demand = 0.75;  % Reduced baseload to trigger xenon transient
            return;
        end

        % Normal daily cycling (0-48 hours)
        cycle_hours = params.load_cycle_hours;  % 24 hours
        t_mod = mod(t_hours, cycle_hours);

        % Validate arrays before interpolation
        if ~isfield(params, 'load_cycle_points') || ~isfield(params, 'load_cycle_values')
            fprintf('WARNING: load_cycle arrays missing in params\n');
            P_demand = 0.8;
            return;
        end

        if length(params.load_cycle_points) ~= length(params.load_cycle_values)
            fprintf('WARNING: load_cycle arrays have different lengths\n');
            P_demand = 0.8;
            return;
        end

        if length(params.load_cycle_points) < 2
            fprintf('WARNING: load_cycle arrays too short\n');
            P_demand = 0.8;
            return;
        end

        % Interpolate from load profile points
        P_demand = interp1(params.load_cycle_points, params.load_cycle_values, ...
                           t_mod, 'linear', 'extrap');

        % Clamp to reasonable range
        P_demand = max(min(P_demand, 1.05), 0.60);

    else
        % Scenarios A and B: Simple ramp profile
        if t < params.demand_ramp_up_start
            P_demand = 1.0;
        elseif t < params.demand_ramp_up_end
            fraction = (t - params.demand_ramp_up_start) / ...
                (params.demand_ramp_up_end - params.demand_ramp_up_start);
            P_demand = 1.0 + params.demand_magnitude * fraction;
        elseif t < params.demand_hold_end
            P_demand = 1.0 + params.demand_magnitude;
        elseif t < params.demand_ramp_down_end
            fraction = 1 - (t - params.demand_hold_end) / ...
                (params.demand_ramp_down_end - params.demand_hold_end);
            P_demand = 1.0 + params.demand_magnitude * fraction;
        else
            P_demand = 1.0;
        end
    end

catch ME
    fprintf('ERROR in SMR_Demand at t=%.3f: %s\n', t, ME.message);
    P_demand = 0.8;  % Safe fallback
end

end