function [header header_short]= NXheader_read(file)

% Reads header information for the NeXus format for storing x-ray
% tomography data
%
% (c) Robert S Bradley 2015

header.File = file;
header.FileContents = 'Projection images'; %Are there other types?!

%Convert NeXus hdf5 file to header structure
s = h5struct(file);

%Read essential info
info = NXheader_info;

s1 = expand_structure(eval(['s.' info.path]), ['s.' info.path], {'',''});

%Create hdr from known path
to_do = zeros(size(info.names,1) ,1);
for n = 1:size(info.names,1)    
    str_inds =find(cellfun(@(x) ~isempty(x),strfind(s1(:,1), info.names{n,2}), 'UniformOutput', 1));    
    if ~isempty(str_inds)        
        header.(info.names{n,1}) =   eval(s1{str_inds(1),1});  
        header.DataLocations.(info.names{n,1}) = s1{str_inds(1),1};
    else
        to_do(n) = 1;
    end
end

%If info not found search full structure;
to_do = find(to_do);
if ~isempty(to_do)
    s1 =expand_structure(s, 's', {'',''});
    for n = 1:numel(to_do)
        str_inds =find(cellfun(@(x) ~isempty(x),strfind(s1(:,1), info.names{to_do(n),2}), 'UniformOutput', 1));    
        if ~isempty(str_inds)            
            header.(info.names{to_do(n),1}) =   eval(s1{str_inds(1),1}); 
            header.DataLocations.(info.names{to_do(n),1}) = s1{str_inds(1),1};
        else
        	header.(info.names{to_do(n),1}) = [];
        end
    end  
end

%Adjust data file path (assume data is in same directory as nxs file)
[~, n, e] = fileparts(header.DataFile{1});
pn = fileparts(file);
header.DataFile{1} = [pn '\' n e];

%Get image info
if ~strcmpi(header.DataFile{2}(1), '/')
    header.DataFile{2} = ['/' header.DataFile{2}];
end

data_info = h5info(header.DataFile{1}, header.DataFile{2});
sz = data_info.Dataspace.Size;

header.ImageWidth = sz(1);
header.ImageHeight = sz(2);
header.ImageIndex = find(header.ImageKey==info.imagekey.images);
header.NoOfImages = numel(header.ImageIndex);

switch data_info.Datatype.Type
    case 'H5T_IEEE_F32LE'
        header.DataType = 'single';
    case 'H5T_IEEE_F32BE'
        header.DataType = 'single';
    case 'H5T_IEEE_F64LE'
        header.DataType = 'double';
    case 'H5T_IEEE_F64BE'
        header.DataType = 'double';
    case 'H5T_STD_U8LE'
        header.DataType = 'uint8';
    case 'H5T_STD_U8BE'
        header.DataType = 'uint8';    
    case 'H5T_STD_U16LE'
        header.DataType = 'uint16';
    case 'H5T_STD_U16BE'
        header.DataType = 'uint16'; 
end


%Check on distances and units
if ~isnumeric(header.R2)
    header.R2 = 0;
end
att = h5info(file, strrep(header.DataLocations.R2(2:end-6), '.','/'));
u_ind = strcmpi({att.Attributes.Name}, 'Units');
if u_ind
   header.Units = att.Attributes(u_ind).Value;    
else
    header.Units = 'mm';
end
if ~isnumeric(header.PixelSize)
    header.PixelSize = [];
end
att = h5info(file, strrep(header.DataLocations.PixelSize(2:end-6), '.','/'));
u_ind = strcmpi({att.Attributes.Name}, 'Units');
if u_ind
   header.PixelUnits = att.Attributes(u_ind).Value;    
else
    header.PixelUnits = '';
end

%Process projection images from image key
if strcmpi(header.FileContents(1), 'P') && isnumeric(header.ImageKey);   
   header.Reference.BlackRefs.Mode = 'single';
   header.Reference.BlackRefs.Images = find(header.ImageKey==info.imagekey.blackrefs);   
  
   %Read black refs
   nbr = numel(header.Reference.BlackRefs.Images);
   br = 0;
   
   opts.Title = 'NXheader_read';
   opts.InfoString = 'Reading black reference images....';
   wb = TTwaitbar(0, opts);
   pause(0.01);
   for n = 1:nbr
      tmp = double(NXimage_read(header,n,0,0,info.imagekey.blackrefs));
      %tmp = remove_extreme_pixels1(tmp, [9 9], 10, 'local');      
      br = br+tmp;
      TTwaitbar(n/nbr, wb);
   end
   close(wb);
   tmp = br/nbr;
   tmp = remove_extreme_pixels1(tmp, [9 9], 8, 'local');  
   header.Reference.BlackRefs.Data = tmp;
   
   header.Reference.WhiteRefs.Mode = 'single';
   header.Reference.WhiteRefs.Images = find(header.ImageKey==info.imagekey.whiterefs);
   
   
   %Read white refs
   nbw = numel(header.Reference.WhiteRefs.Images);
   bw = 0;   
   opts.Title = 'NXheader_read';
   opts.InfoString = 'Reading white reference images....';
   wb = TTwaitbar(0, opts);
   pause(0.01);
   for n = 1:nbw           
      tmp = double(NXimage_read(header,n,0,0,info.imagekey.whiterefs));
      %tmp = remove_extreme_pixels1(tmp, [9 9], 10, 'local');  
      bw = bw+tmp;
      TTwaitbar(n/nbw, wb);
   end
   close(wb);
   
   tmp = bw/nbw-header.Reference.BlackRefs.Data;
   header.Reference.WhiteRefs.Data = remove_extreme_pixels1(tmp, [9 9], 8, 'local');  
end

%Create short header
 header_short.File = header.File;
 header_short.FileContents = header.FileContents;
 header_short.PixelSize = header.PixelSize;
 header_short.PixelUnits = header.PixelUnits;
 header_short.R1 = Inf;
 header_short.R2 = header.R2;
 header_short.Angles = header.Angles(header.ImageIndex);
 header_short.Units = header.Units;
 header_short.ImageWidth = header.ImageWidth;
 header_short.ImageHeight = header.ImageHeight;
 header_short.NoOfImages = header.NoOfImages;
 header_short.DataType = header.DataType;
 header_short.ExposureTime = header.ExposureTime;
 header_short.ApplyRef = 1;
 header_short.RotBy90 = 1;
 header_short.ROIread = 1;
% if isfield(header, 'DataRange')
%        header_short.DataRange = header.DataRange;
% else
%     header_short.DataRange = [];
% end
 header_short.read_fcn = @(x, tmp) NXimage_read(header,x, tmp{1}, tmp{2},0);
