% Very elementary FM radio demodulator. It requires a file with analytic 
% signal as an imput.
%
% Jiri Fajtl <ok1zjf@gmail.com>
% Free to use for everyone
%

% BBC Oxford - 95.2 FM
filename = '../capture-95200-2M.bin';

cwfs = 2000000; % Carrier wave sampling frequency
demodfs = 200000; % Sampling freqeuncy (200KHz) we use for our FM demodulator
audioFS = 48000; % Sampling frequency of the output audio stream
% The audio will get saved to a file with filename+'.pcm' in raw format
% Mono, Signed 16 bits integer

fid = fopen(filename,'rb');
y = fread(fid,'uint8=>double');
y = y-127; % convert to signed ch ar

% Create complex numbers from the I and Q streams
% Odd samples are I, even Q
y = y(1:2:end) + i*y(2:2:end);


%-------------------------------------------------------------------------
% The following code actually does the demodulation

% Subsample to fs=200KHz from 2MHz
% Low pass first with cutoff ~ fs/2
subsample = floor(cwfs/demodfs)
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

% Low pass and subsample the audio to the audioFS sampling rate
% You can calculate the Fc the same way as above

% This subsampling is very inacurate if the audioFS is not an integer
% multiplier of the demodfs. In that case the audio will play
% slightly faster or slower.
subsample = round(demodfs/audioFS)
windowSize = 2*subsample;
kernel = ones(1,windowSize)/windowSize;
pcm = filter(kernel, 1, pcm);
pcm = pcm(1:subsample:end);
pcm = pcm ./ pi; % Convert the the angle (±pi) to ±1

%----------------------------------------------------------------------
% The following is just a file output and playback in Matlab

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
ap = audioplayer(pcm, audioFS);
ap.play()
pause;
ap.pause();
