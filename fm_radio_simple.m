% Very elementary FM radio demodulator. It requires a file with analytic 
% signal as an input.
%
% Jiri Fajtl <ok1zjf@gmail.com>
% Free to use for everyone
% 
% History
%   12.3.2013 - Modified the audio stream downsampling to produce an accurate
%               target sampling rate
%   
%   14.3.2013 - Forked this file from the fm_demod_simple.m. Added a detection
%               of the multiple program carriers in the spectrum, plot of 
%               the input and down/up mixed spectrum and the complex mixer.
%               
%

% Download binary IQ files from:
%      http://daigazou.com/sdr/capture-95200-2M.bin.zip
%      http://daigazou.com/sdr/capture-102000-2M.bin.zip

% BBC Oxford - 95.2 FM
%filename = '../capture-95200-2M.bin';

% Tuner frequency 102.0 MHz
% Carrier 1: +600Khz = Heart FM ??
% Carrier 2: -700Khz = Classic FM
f0 = 102000000; % in Hz
filename = '../capture-102000-2M.bin';


cwfs = 2000000; % In Hz. Carrier wave sampling frequency
demodFs = 200000; % in Hz. Sampling freqeuncy (200KHz) we use for our FM demodulator
audioFs = 48000; % in Hz. Sampling frequency of the output audio stream
% The audio will get saved to a file with filename+'.pcm' in raw format
% Mono, Signed 16 bits integer

accurateSubsampling = false; % If true the audio downsampling will be done to
% the exact audioFs otherwise to an integer of  demodFs/demodFs

carrierDelta = 0;  
carrierDelta = 600000; % in +/- Hz If the program carrier is not at the 
% origin set the offset here in Hz. If it's zero the program will try to
% detect all carriers in the spectrum and selects the first one.

%-------------------------------------------------------------------------
% Read file with the samples
%-------------------------------------------------------------------------
fid = fopen(filename,'rb');
y = fread(fid,'uint8=>double');
y = y-127; % convert to signed char

% Create complex numbers from the I and Q streams
% Odd samples are I, even Q
y = y(1:2:end) + i*y(2:2:end);

%-------------------------------------------------------------------------
% Show the power spectrum of the input signal
%-------------------------------------------------------------------------
fftlen = 4096;
[n m] = size(y);
s = floor(n / fftlen)
y = y(1:s*fftlen);
x = reshape(y, fftlen, s); 
yf = fft(x,[],1);

% plot signal
X = fftshift(yf, 1); 
pSpect = mean(abs(X).^2, 2); 

binWidth = cwfs/fftlen;
f=linspace(0, 1, fftlen);
f = cwfs*f-cwfs/2;
f = f/1e3;
figure(1); plot(f, 10*log10(pSpect(1:fftlen))); 
xlabel('KHz'); ylabel('Gain (dB)');

% Find possible carriers in the spectrum
[pks,locs] = findpeaks(pSpect, ...
        'MINPEAKDISTANCE', round(100000 / binWidth), ...
        'MINPEAKHEIGHT', 1e8);
                        
carriers = (locs+1-(fftlen/2)) * binWidth;
disp('Found carriers. Relative to sampled frequency band. In KHz.')
disp(carriers/1e3)

disp('Found carriers. Absolute frequency in MHz.')
(carriers+f0)/1e6


%--------------------------------------------------------------------------
% Qadrature mixer
%--------------------------------------------------------------------------
% Down/Up shift a given carrier to the origin. If the carrier was not specified
% use the first that we found.
if carrierDelta == 0
    carrierDelta = carriers(1)
end

% If the carrier is zero we don't have to do any mixing here.
if ~carrierDelta == 0    
    
    % Create a complex oscillator with frequency 
    % by which we need to reduce or advance the freq spectrum.
    n = 1:length(y);
    t = 1/cwfs; % This is the main sampling interval
    z = cos(carrierDelta*2*pi*t*n)';
    oscCplx = hilbert(z);
    
    % To rotate clockwise get a complex conjugate of the local oscillator.
    if carrierDelta > 0
        oscCplx = conj(oscCplx);
    end
    
    % Multiply our signal with the oscillator signal. Multiplication of 
    % complex numbers will move the phasor.
    y = y.*oscCplx;
end

%-------------------------------------------------------------------------
% Show the power spectrum after the mixer
%-------------------------------------------------------------------------
fftlen = 4096;
[n m] = size(y);
s = floor(n / fftlen)
y = y(1:s*fftlen);
x = reshape(y, fftlen, s); 
yf = fft(x,[],1);

% plot signal
X = fftshift(yf, 1); 
pSpect = mean(abs(X).^2, 2); 

binWidth = cwfs/fftlen;
f=linspace(0, 1, fftlen);
f = cwfs*f-cwfs/2;
f = f/1e3;
figure(2); plot(f, 10*log10(pSpect(1:fftlen))); 
xlabel('KHz'); ylabel('Gain (dB)');


%-------------------------------------------------------------------------
% FM complex baseband delay demodulator
%-------------------------------------------------------------------------
% Subsample to fs=200KHz from 2MHz
% Low pass first with cutoff ~ fs/2
subsample = floor(cwfs/demodFs)
kernelLength = subsample;

% We use a moving average filter with the kernel size of 'subsample' this 
% will give us cutoff freqeuncy (-3dB) about
% Fc ~ cwfs * 0.443 / kernelLength
% Fc ~ 88.6KHz
% Or if you like it is: H(?) = 1/N ?(k=0, N) e^(-j?k) where N=kernel length
% Which is: H(?) = ?(k=0,N) a^k = [1 - a^(N-1)]/(1-a)
% so H(?) = 1/N [1-e^(-j?N)] / [1-e^(-j?)]
% The smallest ? for |H(?)|^2 = 1/2 is the Fc 
kernel = ones(1,kernelLength)/kernelLength;
y = filter(kernel, 1, y);

% and finally downsample the signal. Pick every 'subsample' sample
y = y(1:subsample:end);

% Create n-1 delayed copy of our signal. Simply shift all samples to the 
% right by one. Set the first sample to zero and discard the last one.
yd = [0; y(1:end-1)]; 

% FM discriminator (http://en.wikipedia.org/wiki/Frequency_modulation)
% Get the phase shift of the complex phasor between n and n-1 samples
% This corresponds to freqeuncy changes of our carrier wave which 
% corresponds to the amplitude of our original audio signal.
% To get the phase difference multiply the y[n] with the complex conjugate
% of y[n-1] and find the angle in radians
yf = y .* conj(yd);
pcm = angle(yf);

% Bacially this angle directly corresponds to the amplitude of the audio
% signal. 

%-------------------------------------------------------------------------
% Plot the average power of the audio freqeuncy spectrum before subsampling
%-------------------------------------------------------------------------
% We can see other interesting information such as the 19KHz pilot for
% the stereo decoding or RDS data stream. Only the positive frequencies
fftlen = 1024;
[n m] = size(pcm);
s = floor(n / fftlen)
x = pcm(1:s*fftlen); % Trim the lenght of the seqeunce so it is an integer
% multiplier of the fftlen
x = reshape(x, fftlen, s);  % reshape to sequences of the fftlength
X = fft(x,[],1); % run fft on all columns of the x

% plot signal
%X = fftshift(X, 1); % compute the spectrum
Xpwr = mean(abs(X).^2, 2); % Compute average power spectrum

% Create series for the x axis 
f=linspace(0,1,fftlen/2+1);
f = f * demodFs/2;
f = f./1e3; % Show the freqeuncies in KHz 
figure(3); plot(f , 10*log10(Xpwr(1:fftlen/2+1)))
xlabel('KHz'); ylabel('Gain (dB)');


%-------------------------------------------------------------------------
% Downsample to the target audio framerate
%-------------------------------------------------------------------------

% Low pass and subsample the audio to the audioFs sampling rate
% You can calculate the Fc the same way as above

% This subsampling is very inacurate if the audioFs is not an integer
% multiplier of the demodfs. In that case the audio will play
% slightly faster or slower.
subsample = round(demodFs/audioFs);

if accurateSubsampling
    % To get an accurate downsampling we first upsample to the lowest 
    % common multiplier of the source and target sampling rate (highAudioFs)
    % then low pass filter and downsample by a ratio highAudioFs/audioFs
    % which will be an integer.
    highAudioFs = lcm(demodFs, audioFs);
    uprate = highAudioFs/demodFs;
    
    % In Octave >3.8 with signal package and in Matlab you can use
    % function upsample() and downsample() instead of the following
    %pcm = upsample(pcm, uprate);    
    y = zeros(uprate*size(pcm,1), 1);
    y(1:uprate:end, :) = pcm;
    pcm = y; 
    
    subsample = highAudioFs/audioFs;
 end

windowSize = subsample;
kernel = ones(1,windowSize)/windowSize;
pcm = filter(kernel, 1, pcm);
pcm = pcm(1:subsample:end);
pcm = pcm ./ pi; % Convert the angle (±pi) to ±1


%----------------------------------------------------------------------
% The following is just a file output and playback in Matlab
%-------------------------------------------------------------------------

% Convert to signed in16 ±32767
% You can change it here to int8 (char) if you like
pcm16 = pcm .* 32767;

% Save the audio to a file as a signed 16 bits int
% To play it with sox (on Linux and Mac)
% play -r 48000 -t s16 -L -c 1 capture.bin.pcm
% Or you can import it as a raw file in Audacity in almost any OS you like.
filenameOut = [filename, '.pcm'];
fid = fopen(filenameOut, 'w');
fwrite(fid, pcm16, 'int16');
fclose(fid);

% This will play the audio in Matlab directly
% Hit any key to stop the playback
ap = audioplayer(pcm, audioFs);
ap.play()
pause;
ap.pause();
