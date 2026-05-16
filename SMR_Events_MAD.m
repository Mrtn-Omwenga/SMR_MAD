function [value, isterminal, direction] = SMR_Events_MAD(t, y, params)
% SMR_Events_MAD.m - FIXED VERSION for 20-state MAD model
% Event function to stop simulation if reactor goes unstable
%
% FIXES:
% 1. Handles 20-state vector (includes PCM state)
% 2. Added PCM temperature safety check
% 3. Graceful handling of incomplete state vectors

% Default outputs
value = [1; 1; 1; 1];
isterminal = [1; 1; 1; 1];
direction = [0; 0; 0; 0];

% Only compute events if y is a vector with at least 2 elements
if isnumeric(y) && length(y) >= 2
    P_total = y(1) + y(2);
    value(1) = P_total - 6.0;    % Power exceeds 300% of nominal
    value(3) = 0.02 - P_total;   % Power drops below 1%
end

% Check fuel temp if y has at least 17 elements
if isnumeric(y) && length(y) >= 17
    T_fuel = y(17);
    value(2) = T_fuel - 1000;    % Fuel temperature exceeds 1000C
end

% Check PCM temp if y has at least 20 elements (MAD-specific)
if isnumeric(y) && length(y) >= 20
    T_pcm = y(20);
    value(4) = T_pcm - 100;      % PCM temperature exceeds 100C (safety)
end

end