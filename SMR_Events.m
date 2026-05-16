function [value, isterminal, direction] = SMR_Events(t, y, params)
% SMR_Events.m - Event function to stop simulation if reactor goes unstable

P_total = y(1) + y(2);
T_fuel = y(17);

% Event 1: Power exceeds 300% of nominal (runaway)
value(1) = P_total - 6.0;
% Event 2: Fuel temperature exceeds 1000C (meltdown)
value(2) = T_fuel - 1000;
% Event 3: Power drops below 1% (shutdown)
value(3) = 0.02 - P_total;

isterminal = [1; 1; 1];  % Stop integration for all events
direction = [0; 0; 0];   % Detect in either direction

end