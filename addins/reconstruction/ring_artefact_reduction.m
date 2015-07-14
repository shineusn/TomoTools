function [s_out, methods] = ring_artefact_reduction(s_in, method, params)


%s_in: input sinogram with angles as rows and detector elements as columns.

methods = {'raven', {9 0.9}, @(s,p) ring_artefact_reduction(s, 'raven', p);...
            'median', {7,9}, @(s,p) ring_artefact_reduction(s, 'median', p);...
            'gaussian-median', {11,9,1}, @(s,p) ring_artefact_reduction(s, 'gaussian-median', p);...
            'line ratios', {Inf,5}, @(s,p) ring_artefact_reduction(s, 'line ratios', p);...
            'wavelet-fourier', {'db25', 5, 2.4}, @(s,p) ring_artefact_reduction(s, 'wavelet-fourier', p)};
        
if nargin<1
    s_out = [];
    return;    
end
params
if size(s_in,3)>1
    s_out = zeros(size(s_in));
    for nn = 1:size(s_in,3)
        s_out(:,:,nn) = ring_artefact_reduction(s_in(:,:,nn), method, params);
    end
    return;
end



switch method
    

    case 'raven'
        %butterworth filter
        [b,a]=butter(params{1},params{2}, 'low');
        s_inp = padarray(s_in, [0 20], 'replicate');
        s_tmp=filter(b,a,s_inp')';        
        %s_tmp = s_in-s_tmp(:,21:end-20);
        %s_tmp1 = do_section(s_tmp, params{1});
        
        %s_out = s_in-s_tmp1;
        s_out = s_tmp(:,21:end-20);
        
    case 'median'
                
        %s_tmp = s_in-medfilt2(s_in,[1 params{2}]);
       %s_tmp1 = do_section(s_tmp, params{1});
        
        %s_out = s_in-s_tmp1;
        s_tmp1 = do_section(s_in,params{1});        
        s_tmp2 = s_tmp1-medfilt2(s_tmp1, [1 params{2}]);
        s_out = s_in-s_tmp2;

    case 'gaussian-median'    
        
        s_tmp = s_in-imfilter(s_in,fspecial('gaussian', 3*params{1}*[1 1], params{1}), 'replicate');
        s_tmp1 = do_section(s_tmp,params{3});        
        s_tmp2 = s_tmp1-medfilt2(s_tmp1, [1 params{2}]);
        s_out = s_in-s_tmp2;
        
    case 'moving average'
        
        ssum = mean(s_in,1)-movingmean(mean(s_in,1)',params{1})';
        
        s_tmp = s_in-movingmean(s_in,params{1},1);
        s_tmp1 = do_section(s_tmp, params{1});
        
        s_out = s_in-s_tmp1;


    case 'line ratios'
        
        ds = zeros(size(s_in));
        ds(:,2:end) = diff(s_in,[],2);
        ds = 1+ds./s_in;
        ds(s_in>params{1}) = Inf;
        dsmed = median(ds,1);
        dsprod = cumprod(dsmed,2);
        dsprod_sm = medfilt1(dsprod, params{2});
        
        %dsprod_sm = imfilter(dsprod, fspecial('gaussian', [1 3*params{2}], params{2}),'replicate');
        dr = repmat(dsprod-dsprod_sm,[size(s_in,1) 1]);
        s_out = s_in./(1+dr);
        
    case 'wavelet-fourier'
        
        % wavelet decomposition
        Ch = cell(params{2},1);
        Cv = cell(params{2},1);
        Cd = cell(params{2},1);
        s = s_in;
        for ii=1:params{2}
            [s,Ch{ii},Cv{ii},Cd{ii}]=dwt2(s,params{1});
        end
        
        

         % FFT transform of horizontal frequency bands
         for ii=1:params{2}
            % FFT
            fCv=fftshift(fft(Cv{ii}));
            [my,mx]=size(fCv);

            % damping of vertical stripe information
            damp=1-exp(-[-floor(my/2):-floor(my/2)+my-1].^2/(2*params{3}^2));
            fCv=fCv.*repmat(damp',1,mx);

            % inverse FFT
            Cv{ii}=ifft(ifftshift(fCv));
         end

         % wavelet reconstruction
         s_out=s;
         for ii=params{2}:-1:1
            s_out=s_out(1:size(Ch{ii},1),1:size(Ch{ii},2));
            s_out=idwt2(s_out,Ch{ii},Cv{ii},Cd{ii},params{1});
         end
        
         s_out = s_out(1:size(s_in,1), 1:size(s_in,2));
         
        

end


    function so = do_section(si, N)
       
        so = si;
        Nrows = floor(size(si,1)/N);
        r = 1:Nrows:size(si,1);
        r(end) = size(si,1);
        for n = 2:numel(r)
            
            stmp = mean(si(r(n-1):r(n), :),1);
            so(r(n-1):r(n),:) = repmat(stmp, [r(n)-r(n-1)+1,1]);
            
        end
        
        
        
        
    end

end