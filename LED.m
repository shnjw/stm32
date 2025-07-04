% 오디오 파일을 읽어 데이터와 샘플링 주파수 얻기
[audioData, fs] = audioread('Too Cool To Die.mp3');

% 모노 오디오 데이터 생성
monoAudio = mean(audioData, 2);

% 스펙트로그램 계산
windowLength = 1024; % 윈도우 길이
noverlap = 512; % 오버랩 샘플 수

%{
% 템포 계산 (전체 오디오의 템포)
miraudioObject = miraudio(monoAudio, fs);
tempoStruct = mirtempo(miraudioObject);
tempo = mirgetdata(tempoStruct); % 숫자형 변수로 변환
%}

% 0.5초 간격으로 구간 나누기
segmentDuration = 0.5; % 0.5초
segmentSamples = segmentDuration * fs; % 각 구간의 샘플 수
totalSamples = length(monoAudio); % 전체 샘플 수
numSegments = floor(totalSamples / segmentSamples); % 구간의 총 개수

% 각 구간별 키를 저장할 배열 초기화
keys = cell(numSegments, 1);
hue = zeros(numSegments, 1);
saturation = zeros(numSegments, 1);
value = zeros(numSegments, 1);

% envelop 계산을 위한 배열 초기화
envelopes = zeros(numSegments, 1);

% 각 구간에 대해 키, 주파수, 최대 진폭 추출
for i = 1:numSegments
    % 각 0.5초 구간에 해당하는 오디오 데이터 추출
    segmentStart = (i - 1) * segmentSamples + 1;
    segmentEnd = min(i * segmentSamples, totalSamples);
    segmentData = monoAudio(segmentStart:segmentEnd);

    %{
    % Mirtoolbox를 사용하여 키 추출
    miraudiofile = miraudio(segmentData, fs);
    keyD = mirkey(miraudiofile);
    key = mirgetdata(keyD);
    keys{i} = key;
    %}

    % 주파수 특징 계산
    [S, F, ~, ~] = spectrogram(segmentData, windowLength, noverlap, [], fs);
    segment = mean(abs(S), 2); % 각 구간의 스펙트럼 평균
    weightedFrequencies = F .* segment; % 주파수와 진폭의 곱
    meanFrequency = sum(weightedFrequencies) / sum(segment); % 가중 평균 주파수

    % 주파수 -> 색상(Hue) 매핑
    minFreq = 2000;
    maxFreq = 8000;
    normalizedFrequency = (meanFrequency - minFreq) / (maxFreq - minFreq);
    hue(i) = min(max(normalizedFrequency, 0), 1);  % 0~1 범위로 정규화
    
    % 최대 진폭, 최소 진폭, 평균 진폭 계산
    peakAmplitude = max(abs(segmentData));
    minAmplitude = min(abs(segmentData));
    meanAmplitude = mean(abs(segmentData));

    % 진폭 -> 채도(Saturation) 매핑 (각 세그먼트 내에서 정규화)
    % 평균 진폭을 중심으로 정규화
    normalizedSaturation = (peakAmplitude - meanAmplitude) / (peakAmplitude - minAmplitude + eps);
    saturation(i) = min(max(normalizedSaturation, 0), 1);  % 0~1 범위로 정규화

    % 엔벨로프 계산
    [envUpper, envLower] = envelope(segmentData);
    envelopeAmplitude = mean(envUpper); % 엔벨로프의 평균 진폭 계산

    % RMS 에너지 계산 (음량 크기)
    rmsEnergy = sqrt(mean(segmentData .^ 2));

    % 엔벨로프 값 저장
    value(i) = min(max(envelopeAmplitude + rmsEnergy + 0.1, 0), 1);

    %{
    % 키 -> 색상 명도(Value) 매핑
    if ~isempty(key) && isnumeric(key) % 키가 비어 있지 않고 숫자로 저장된 경우
        value(i) = min(max((key / 12) + envelopeAmplitude, 0), 1); % 키 값에 엔벨로프 값을 더해 저장
    else
        value(i) = min(max(envelopeAmplitude, 0), 1); % 유효하지 않은 키일 경우 엔벨로프 값만 사용
    end
    %}
end

% HSV 색상 생성 (스펙트럼 중심 주파수를 hue로, 최대 진폭을 saturation으로, 엔벨로프 값을 value로 매핑)
HSV = [hue(:), saturation(:), value(:)];  % 0~1 범위로 정규화

% HSV 값 출력
disp('HSV 값:');
disp(HSV);

% HSV -> RGB 변환
RGB = hsv2rgb(HSV);

% RGB 값을 [0, 255] 범위로 변환
RGB_STM32 = uint8(RGB * 255);

% 변환된 RGB 값 출력
disp('STM32에서 사용될 RGB 값:');
disp(RGB_STM32);

% 오디오 플레이어 객체 생성
player = audioplayer(monoAudio, fs);

% 시각화 설정
figure;
hold on;
h = patch([0, 1, 1, 0], [0, 0, 1, 1], RGB(1, :), 'EdgeColor', 'none'); % 전체 영역을 색상으로 채울 patch 객체
xlim([0, 1]);
ylim([0, 1]);
axis off; % 축 제거
title('Real-time Color Representation');

% 오디오 재생과 함께 시각화 업데이트
play(player);
startTime = tic;

s = serialport('COM3',115200);
for j = 1:numel(RGB_STM32)
    write(s, RGB_STM32(j), "uint8");  % 각 원소를 uint8 형식으로 전송
    pause(0.169);  % 작은 대기 시간 추가 (필요시)
end
clear s;

for i = 1:numSegments
    % 색상 업데이트
    set(h, 'FaceColor', RGB(i, :));
    % 색상 업데이트 간격 조정
    pause(segmentDuration); % 0.5초 구간에 맞춰 색상 업데이트  
end
