clc; clear; close all;

% ==============================================================
% PHASE 1: DATA PREPARATION
% ==============================================================
filename = 'C:\Users\Path Bhimani\Downloads\Solar Power Generation Data.xlsx';
df = readtable(filename, 'PreserveVariableNames', true);

df.Properties.VariableNames{1} = 'Overall_Power';
df.Properties.VariableNames{2} = 'Time_start';
df.Properties.VariableNames{3} = 'Time_end';
df.Properties.VariableNames{4} = 'Date';

df.Date = fillmissing(df.Date, 'previous');
df.Overall_Power = fillmissing(df.Overall_Power, 'previous');

series = df.Overall_Power;

% ==============================================================
% PHASE 2: TRAINING SPLIT
% ==============================================================
training_series = [series(1:27840); series(30817:35136)];

% ==============================================================
% PHASE 3: ADF TEST
% ==============================================================
[h,pValue] = adftest(training_series);

fprintf('\nADF Test p-value: %.5f\n', pValue);
if h == 1
    disp('Series is stationary');
else
    disp('Series NOT stationary → Differencing required');
end

% ==============================================================
% PHASE 4: ACF & PACF (UPDATED SYNTAX)
% ==============================================================
figure('Position',[100,100,1400,500]);

subplot(1,2,1);
autocorr(training_series, 'NumLags', 500);
title('ACF Plot (q and Q)', 'FontSize', 16);
set(gca, 'FontSize', 12);

subplot(1,2,2);
parcorr(training_series, 'NumLags', 500);
title('PACF Plot (p and P)', 'FontSize', 16);
set(gca, 'FontSize', 12);

% ==============================================================
% PHASE 5: SOLAR PROFILE (ONE DAY)
% ==============================================================
day_index = 10;
s = (day_index-1)*96 + 1;
e = s + 95;

figure;
plot(series(s:e), 'LineWidth', 2);
title(sprintf('Solar Profile - Day %d', day_index), 'FontSize', 16);
xlabel('Time (15-min intervals)', 'FontSize', 14);
ylabel('Power (MW)', 'FontSize', 14);
set(gca, 'FontSize', 12);
grid on;

% ==============================================================
% PHASE 6: SARIMA PARAMETERS
% ==============================================================
d = 1; D = 1; seasonal_lag = 96;

best_p = 3;
best_q = 3;
best_P = 2;
best_Q = 1;

forecast_steps = 16; % CHANGE THIS (8, 32, 96)

% ==============================================================
% PHASE 7: FORECASTING
% ==============================================================
Num_forecast_days = 31;
start_idx = 27841;
step = 96;
total_steps = Num_forecast_days * step;
end_idx = start_idx + total_steps - 1;

forecasted_values = zeros(total_steps,1);
actual_values = zeros(total_steps,1);
current_series = training_series;

disp('Starting Forecasting...');

for i = start_idx : step : (end_idx - step + 1)
    
    args = {'D',1,'Seasonality',seasonal_lag};
    if best_p>0, args=[args,{'ARLags',1:best_p}]; end
    if best_q>0, args=[args,{'MALags',1:best_q}]; end
    if best_P>0, args=[args,{'SARLags',seasonal_lag*(1:best_P)}]; end
    if best_Q>0, args=[args,{'SMALags',seasonal_lag*(1:best_Q)}]; end
    
    Mdl = arima(args{:});
    estMdl = estimate(Mdl,current_series,'Display','off');
    
    daily_history = current_series;
    
    for j = 1:forecast_steps:step
        
        cur_steps = min(forecast_steps, step-j+1);
        idx = i + j - 1;
        
        [forecast_vals,~] = forecast(estMdl, cur_steps, 'Y0', daily_history);
        forecast_vals(forecast_vals<0)=0;
        
        actual_vals = series(idx:idx+cur_steps-1);
        
        save_start = idx - start_idx + 1;
        save_end = save_start + cur_steps - 1;
        
        forecasted_values(save_start:save_end) = forecast_vals;
        actual_values(save_start:save_end) = actual_vals;
        
        daily_history = [daily_history; actual_vals];
    end
    
    current_series = [current_series; series(i:i+step-1)];
end

disp('Forecasting Complete');

% ==============================================================
% PHASE 8: METRICS
% ==============================================================
forecasted_values = round(forecasted_values, 1);
errors = actual_values - forecasted_values;

MAE = mean(abs(errors));
RMSE = sqrt(mean(errors.^2));

SST = sum((actual_values - mean(actual_values)).^2);
SSE = sum(errors.^2);
R2 = 1 - (SSE/SST);

fprintf('\nMAE: %.2f\nRMSE: %.2f\nR2: %.4f\n', MAE, RMSE, R2);

% ==============================================================
% PHASE 9: MAIN PLOT
% ==============================================================
% ==========================================
% PHASE 9: MAIN PLOT (FIXED X-AXIS → DAYS)
% ==========================================
figure('Position',[100,100,1400,500]);

points_per_day = 96;
num_days = length(actual_values) / points_per_day;

% Create day-based x-axis
x_days = (1:length(actual_values)) / points_per_day;

plot(x_days, actual_values, 'LineWidth', 1.5); hold on;
plot(x_days, forecasted_values, '--', 'LineWidth', 1.5);

title('Actual vs Predicted (30 Days)', 'FontSize', 16);
xlabel('Days', 'FontSize', 14);
ylabel('Power (MW)', 'FontSize', 14);

legend('Actual','Predicted','FontSize',14);
set(gca, 'FontSize', 14);
grid on;

% Optional: show integer day ticks
xticks(1:1:num_days);

% ==============================================================
% PHASE 10: SINGLE DAY (8,32,96)
% ==============================================================
day_plot = 5;
s = (day_plot-1)*96+1;
e = s+95;

actual_day = actual_values(s:e);
pred_day = forecasted_values(s:e);

steps_list = [8,32,96];

for k=1:length(steps_list)
    figure;
    plot(actual_day,'LineWidth',2); hold on;
    plot(pred_day,'--','LineWidth',2);
    
    title(sprintf('%d-Step Forecast (Day %d)',steps_list(k),day_plot),'FontSize',16);
    xlabel('Time','FontSize',14);
    ylabel('Power','FontSize',14);
    legend('Actual','Predicted','FontSize',12);
    set(gca, 'FontSize', 12);
    grid on;
end

% ==============================================================
% PHASE 11: BEST & WORST DAY
% ==============================================================
daily_MAE = zeros(Num_forecast_days,1);

for d=1:Num_forecast_days
    s = (d-1)*96+1;
    e = s+95;
    daily_MAE(d)=mean(abs(actual_values(s:e)-forecasted_values(s:e)));
end

[~,best_day]=min(daily_MAE);
[~,worst_day]=max(daily_MAE);

fprintf('Best Day: %d\nWorst Day: %d\n',best_day,worst_day);

% ==============================================================
% PHASE 12: PLOT BEST & WORST DAY WITH ERROR BOUNDS
% ==============================================================
s=(best_day-1)*96+1; e=s+95;
plot_bounds(actual_values(s:e),forecasted_values(s:e),best_day);

s=(worst_day-1)*96+1; e=s+95;
plot_bounds(actual_values(s:e),forecasted_values(s:e),worst_day);

% ==============================================================
% FUNCTION (MUST BE AT END)
% ==============================================================
function plot_bounds(actual, predicted, day)

    upper_5 = actual * 1.05;
    lower_5 = actual * 0.95;

    upper_10 = actual * 1.10;
    lower_10 = actual * 0.90;

    figure;
    hold on;

    plot(actual, 'k', 'LineWidth', 2);
    plot(predicted, 'r--', 'LineWidth', 2);

    plot(upper_5, 'g:', 'LineWidth', 1.5);
    plot(lower_5, 'g:', 'LineWidth', 1.5);

    plot(upper_10, 'b:', 'LineWidth', 1.5);
    plot(lower_10, 'b:', 'LineWidth', 1.5);

    title(sprintf('Day %d Prediction with Error Bounds', day), 'FontSize', 16);
    xlabel('Time (15-min intervals)', 'FontSize', 14);
    ylabel('Power (MW)', 'FontSize', 14);

    legend('Actual','Predicted','+5%','-5%','+10%','-10%', 'FontSize', 12);
    set(gca, 'FontSize', 12);
    grid on;
    hold off;
end

% Test index (original data index)
test_index = (27840 : 27840 + length(actual_values) - 1)';

% Create table
results_table = table(test_index, actual_values, forecasted_values, ...
    'VariableNames', {'Index', 'Actual', 'Predicted'});

% Save to Excel
writetable(results_table, 'test_results.xlsx');