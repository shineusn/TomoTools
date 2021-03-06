function cb_reconstruction_astra(recon_params)


%% Process recon_params optional arguments
if isfield(recon_params, 'options');
    options = recon_params.options;
else
    options = [];
end
if isfield(options, 'show_wb')
    %Show waitbar
    show_wb = options.show_wb;
else
    show_wb = 1;
end
if isfield(options, 'chunk_size')
    %Show waitbar
    chunk_size = options.chunk_size;
else
    chunk_size = 1;
end
if isfield(options, 'detector_shiftx')
    %Detector centre position x
    dsx = options.detector_shiftx;
else
    dsx = 0;
end
if isfield(options, 'detector_shifty')
    %Detector centre position y
    dsy = options.detector_shifty;
else
    dsy = 0;
end
if isfield(options, 'detector_height')
    dh = options.detector_height;
else
    dh = 1; 
end

if isfield(options, 'algorithm')  
    %algorithm
   algorithm =  options.algorithm;
else
   algorithm = 'BP3D_CUDA';
end
if isfield(options, 'iterations')
    %algorithm iterations
   iterations =  options.iterations;
else
   iterations = 1;
end
if isfield(options, 'GPUindex')
    %GPU selection
    GPUindex = options.GPUindex-1;
else
    GPUindex = 0;
end
if isfield(options, 'reconstruction_filter');
    %Filter selection
    filt = options.reconstruction_filter;
else
    filt = 'Ram-Lak';
end       
if isfield(options, 'applymask');
    %Apply mask to recon slices
    options.mask = options.applymask;
    do_mask = 1;
end
if ~isempty(recon_params.ring_artefact_method)
    do_RAR = 1;
    RAR = recon_params.ring_artefact_method;
    RARparams = recon_params.ring_artefact_params;
else
    do_RAR = 0;
end
if isfield(options, 'gpu_memory_limit')
    gpu_mem_limit = options.gpu_memory_limit;
    %Do something?
else
    gpu_mem_limit = Inf;
end
%Currently only support fft centre shift
%centre_shift_mode = [];
% if isfield(options, 'centre_shift_mode');
%     %Filter selection
%     centre_shift_mode = options.centre_shift_mode;
% else
%     centre_shift_mode = 'fft';
%     algorithm = 'BP3D_CUDA';
% end  

%% SET UP GEOMETRY and ASTRA config
angles = recon_params.SD.angles+recon_params.angles_shift;
if max(angles(:))>15    
   angles = angles*pi()/180; 
end
if isempty(recon_params.shifts_crop)
    shifts_crop = 0;
else
    shifts_crop = recon_params.shifts_crop;
end


%Create vectors describing geometry
vectors = zeros(numel(angles),12);
R12 = recon_params.R12;
pixel_size = recon_params.pixel_size;
M = 1+R12(2)/R12(1);

%VECTOR GEOMETRY - DISTANCES ARE RELATIVE TO VOXEL SIZE
%source
vectors(:,1) = sin(angles) * R12(1);
vectors(:,2) = -cos(angles) * R12(1);
%vectors(:,3) = -mid_plane*pixel_size(2);

% center of detector
vectors(:,4) = (-sin(angles) * R12(2)) -dsx*pixel_size(1)*M*cos(angles);
vectors(:,5) = (cos(angles) * R12(2)) -dsx*pixel_size(1)*M*sin(angles);
%vectors(:,6) = mid_plane*pixel_size(2)*R12(2)/R12(1);

%centre shift - to check!
vectors(:,4) = vectors(:,4) -recon_params.centre_shift(1)*pixel_size(1)*cos(angles(:));
vectors(:,5) = vectors(:,5) -recon_params.centre_shift(1)*pixel_size(1)*sin(angles(:)); 

% vector from detector pixel (0,0) to (0,1)
vectors(:,7) = cos(angles)*M*pixel_size(1);
vectors(:,8) = sin(angles)*M*pixel_size(1) ;
vectors(:,9) = 0;

% vector from detector pixel (0,0) to (1,0)
vectors(:,10) = 0;
vectors(:,11) = 0;
vectors(:,12) = M*pixel_size(2);    


proj_geom = astra_struct('cone_vec');
proj_geom.DetectorRowCount = 1;
proj_geom.DetectorColCount = recon_params.SD.dimensions(2)-2*shifts_crop+2*recon_params.pad_options(1);

%Output Volume
output_size = recon_params.output_dims;
vol_geom = astra_create_vol_geom([output_size(1), output_size(2), chunk_size]);
 

cfg = astra_struct(algorithm);
cfg.FilterType = filt;
cfg.option.GPUindex = GPUindex;

if do_mask   
   if numel(options.mask)==1;
       %calculate mask
       [Y, X] = meshgrid(-output_size(2)/2:output_size(2)/2-1, -output_size(1)/2:output_size(1)/2-1); 
       minR = options.mask;
       if minR==0
          minR = floor(recon_params.SD.dimensions(3)/2)+1;          
       end
       options.mask = repmat(single((X.^2 + Y.^2 < minR^2)), [1 1 chunk_size]); 
   else
       %use precalculated mask
        options.mask = single(options.mask);
        if size(options.mask,3)<chunk_size
            options.mask = repmat(options.mask(:,:,1), [1 1 chunk_size]); 
        end
   end
   cfg.option.ReconstructionMaskId = astra_mex_data3d_c('create', '-vol', vol_geom, options.mask);   
end



%% Tiff output structure
%set tiff properties
tagstruct.ImageLength = [];
tagstruct.ImageWidth = [];
tagstruct.Photometric = 1;
tagstruct.Compression = 1;
tagstruct.Software = 'MATLAB:pb_reconstruction';
tagstruct.PlanarConfiguration = 1;
tagstruct.Orientation = 5;
tagstruct.BitsPerSample = 32;
tagstruct.SampleFormat = 3;
tagstruct.SamplesPerPixel = 1;      



%% RUN recon, looping over slices
n_spaces = num2str(numel(num2str(recon_params.SD.dimensions(3))));
s_fmt_str = ['%0' n_spaces 'i'];

global_min = Inf;
global_max = -Inf;

%[Y, X] = meshgrid(-recon_params.output_dims(2)/2:recon_params.output_dims(2)/2-1, -recon_params.output_dims(1)/2:recon_params.output_dims(1)/2-1);

avizo_load_str = '';


if chunk_size==1
    chunk_inds =1:chunk_size:recon_params.SD.dimensions(3)+1;
else
    chunk_inds = 1:chunk_size:recon_params.SD.dimensions(3)+1;
    if chunk_inds(end)<recon_params.SD.dimensions(3)+1;
        chunk_inds(end+1)=recon_params.SD.dimensions(3)+1;
    end
end
count = 0;
if show_wb
    opts.Title = 'TTreconstruction: cone beam';
    opts.InfoString = 'Reconstructing...';
    w = TTwaitbar(0, opts);    
end
row_range_tmp = [-Inf -Inf];
for ns = chunk_inds(1:end-1);
    count = count+1;
    
    %Load sinogram chunks
    istart = chunk_inds(count);
    iend = chunk_inds(count+1)-1;
    
    row_range = conebeam_sinogram_rows(R12, recon_params.pixel_size, [recon_params.SD.dimensions(3) recon_params.SD.dimensions(2)],istart:iend);
    row_range(row_range<1)=[];
    
    %If using equal number of rows above and below recon slices
    %%%if max(row_range(:))>recon_params.SD.dimensions(3)
    %%%    slice_delta = recon_params.SD.dimensions(3)-iend;
    %%%    row_range = istart-slice_delta:iend+slice_delta;
    %%%end
    
    row_range(row_range>recon_params.SD.dimensions(3)) = [];
    dz = (istart+iend)/2-mean(row_range(:));
    
    
    
    %row_range
    %pause
    
    mid_plane = mean(row_range(:))-(dh/2);
    
    rr_istart = find(row_range==istart);
    rr_iend = find(row_range==iend);
    
    nslices = iend-istart+1;
    vol_geom = astra_create_vol_geom(output_size(1), output_size(2), nslices,-output_size(2)/2,output_size(2)/2, -output_size(1)/2, output_size(1)/2,...
                   dz-nslices/2, dz+nslices/2);
    
    %If using equal number of rows above and below recon slices
    %%%vol_geom = astra_create_vol_geom([output_size(1), output_size(2), nslices]);
               
    
    update_str = ['Reconstructing slices ' num2str(istart) ' to ' num2str(iend)];
    fprintf(1, [update_str '....']);
    if show_wb
        opts.InfoString = update_str;
        TTwaitbar((count-1)/(numel(chunk_inds)-1), w,opts);
    end
    tic;
    
    %
    row_max_ind = find(row_range==row_range_tmp(2));
    row_min_ind = row_range_tmp(2)-row_range_tmp(1)+1-row_max_ind+1;
    if isempty(row_max_ind)
        row_max_ind = 0;
    end
    %row_max_ind = 0;
    %Load only unprocessed sinograms    
    if row_max_ind<numel(row_range)
    s = recon_params.SD(:,:,row_range(row_max_ind+1:end));    
    
    %if size(s,3) ~=chunk_size
       %Update vol_geom
        
          
    %end
    
    %Process singram    
    s = s(:,1+shifts_crop:end-shifts_crop,:);  
    s(s==inf) = 0;
    s(isnan(s)) = 0;
    
    %Apply ring removal
    if do_RAR 
        s = RAR(s, RARparams);    
    end  
    
    %Pad   
    if recon_params.pad_options(1)>0
        s = padtovalue(s, [0 recon_params.pad_options(1)], recon_params.pad_options(2));
    end  
   
    do_permute = 1;%CHANGE!!!!!
    s = single(s);   
    if do_permute
         s = permute(s, [2 1 3]); %change to column, angle, row
    end
    
        
    %apply beam hardening correction
    if recon_params.beamhardening>0
        s = (1-recon_params.beamhardening)*s+recon_params.beamhardening*s.^2;
    end
    
    
    %Filter sinogram(s)
    if strcmpi(algorithm(1:2), 'BP')
%         if strcmpi(centre_shift_mode, 'fft') 
%             s = filterProjections(s, filt, Inf, 1, angles, [0 0], recon_params.centre_shift(1));            
%         else  
%             s = filterProjections(s, filt, Inf);
%         end
        s = filterProjections(s, filt, (R12(1)+R12(2)), pixel_size, angles, [dsx dsy+mid_plane]./M);
        
    end
    %stmp1 = s;
   
    if row_max_ind>0        
        s = cat(3,stmp(:,:,row_min_ind:end),s);        
    end
    else
       itmp1 = row_range(1)-row_range_tmp(1)+1;
       itmp2 = row_range(end)-row_range_tmp(1)+1;
       s = stmp(:,:,itmp1:itmp2);
    end
    stmp = s;
     
    
    
    row_range_tmp = [min(row_range), max(row_range)];
    
    %update vectors
    vectors(:,3) = -mid_plane*pixel_size(2);
    vectors(:,6) = mid_plane*pixel_size(2)*R12(2)/R12(1);    
    proj_geom.Vectors = vectors/pixel_size(1);    
    proj_geom.DetectorRowCount = numel(row_range);
    
    %Loop over angle blocks
    ang_block = floor(size(s,2)/floor(((numel(s)+output_size(1)*output_size(2)*(rr_iend-rr_istart+1))*8)/(gpu_mem_limit*1024*1024)));
    ang_blocks = 1:ang_block:size(s,2);
    if ang_blocks(end)<size(s,2)
        ang_blocks = [ang_blocks size(s,2)];
    end
    
    r = zeros([output_size(1), output_size(2), rr_iend-rr_istart+1],'single');    
    for nangs = 1:numel(ang_blocks)-1
    
        proj_geom2 = proj_geom;
        proj_geom2.Vectors = proj_geom2.Vectors(ang_blocks(nangs):ang_blocks(nangs+1)-1,:);        
        sino_id = astra_mex_data3d('create','-sino', proj_geom2, s(:,ang_blocks(nangs):ang_blocks(nangs+1)-1,:));
        rec_id = astra_mex_data3d('create', '-vol', vol_geom);
    
        clear proj_geom2
    
        cfg.ProjectionDataId = sino_id;
        cfg.ReconstructionDataId = rec_id;
    
        alg_id = astra_mex_algorithm('create', cfg);
        tic;
        astra_mex_algorithm('run', alg_id, iterations);
        %astra_mex_algorithm('info')
        %size(r)
        rtmp = astra_mex_data3d('get', rec_id);
        %size(rtmp)
        r = r+rtmp;
        
        astra_mex_data3d('delete', sino_id);
        astra_mex_data3d('delete', rec_id);
        astra_mex_algorithm('delete', alg_id);
    end
    clear s
    
    %crop r
    %r = r(:,:,rr_istart(1)+rr_iend(1));    
    if do_mask>0
        options.mask = repmat(options.mask(:,:,1), [1 1 size(r,3)]);
        r = r.*options.mask;
    end
    
    
    global_min = min(global_min, min(r(:)));
    global_max = max(global_max, max(r(:)));
    
    %write out data---------------------------------------
    if isempty(tagstruct.ImageLength);
        sz = size(r);
        tagstruct.ImageWidth = sz(2);
        tagstruct.ImageLength = sz(1);
    end
   
     
    %Open tiff file for writing
    for nr = 1:size(r,3)
        s_ind = sprintf(s_fmt_str, nr+istart-1);
        tiff_file = Tiff([recon_params.reconstruction_dir '\slice_' s_ind '.tif'], 'w');
        tiff_file.setTag(tagstruct);

        %Write image
        tiff_file.write(r(:,:,nr));
        tiff_file.close();
        
        %Create avizo load string
        sl_pos = strfind([recon_params.reconstruction_dir '\slice_' s_ind '.tif'], '\');
        avizo_load_str  = [avizo_load_str '${SCRIPTDIR}/slice_' s_ind '.tif' ' '];
    
    end
    clear r rtmp tiff_file
    
    t = toc;
    fprintf(1, ['Done in ' num2str(t) 's.\n']);
    

    
end
 
%Tidy up
if show_wb
     close(w);
end

%write out recon slice info
reconstruction.FileType = 'TTxml v1.0';
reconstruction.Format = 'tiffstack';
reconstruction.File = [recon_params.reconstruction_dir '\slice*.tif'];
reconstruction.StackContents = 'Reconstructed slices';
reconstruction.SinogramDir = recon_params.sinogram_dir;
reconstruction.Geometry = 'parallel beam';
reconstruction.Algorithm = algorithm;
reconstruction.iterations = iterations;
reconstruction.ReconFilter = filt;
reconstruction.CentreShift = recon_params.centre_shift;
reconstruction.DataType = 'float32';
reconstruction.NoOfImages = recon_params.SD.dimensions(3);
reconstruction.ImageWidth = output_size(2);
reconstruction.ImageHeight = output_size(1);
[p, u] = getniceunit(recon_params.pixel_size(1), recon_params.pixel_units);
reconstruction.VoxelSize = p;
reconstruction.Units = u;
reconstruction.DataRange = [global_min global_max];
xml_write([recon_params.reconstruction_dir '\reconstruction_info.xml'], reconstruction);

%determine best units

%write out avizo script to load image
sl_pos = strfind(recon_params.file, '\');
am_load_label = recon_params.file(sl_pos(end)+1:end);

hx_file = [recon_params.reconstruction_dir '\load_data.hx'];
fid_hx = fopen(hx_file, 'w');
fprintf(fid_hx, '# Avizo Script\n\n');
fprintf(fid_hx, ['[ load -tif +box ' sprintf('%g ',[0 sz(2)-1 0 sz(1)-1 0 recon_params.SD.dimensions(3)-1]*reconstruction.VoxelSize) '+mode 2 ' avizo_load_str ' ] setLabel ' am_load_label '\n']);
fprintf(fid_hx, create_Avizo_scalebar);
fclose(fid_hx);

end
