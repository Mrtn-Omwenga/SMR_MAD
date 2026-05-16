function P_demand = SMR_Demand_Constant(t, params, scenario)
% SMR_Demand_Constant.m - For fair comparison at fixed power level
% Returns constant demand for Scenario C to eliminate variability

P_demand = 1.0;  % Default

try
    if scenario == 3
        % Constant demand for fair comparison test
        P_demand = 0.78;  % Fixed at 78% power

    else
        % Use original demand for Scenarios A and B
        P_demand = SMR_Demand(t, params, scenario);
    end

catch ME
    fprintf('ERROR in SMR_Demand_Constant at t=%.3f: %s\n', t, ME.message);
    P_demand = 0.78;  % Safe fallback
end

end
