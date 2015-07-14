function img_handle = imager(img, varargin)

% Displays an image in a figure window
%
%   img_handle = imager(img, varargin)
%
%where
%   img_handle = 2-element vector giving the handles to (1) image graphics object
%                (created by built-in function 'image'),(2) the figure.
%          img = image data (2D matrix of real values)
%     varargin = optional input parameter pairs including
%                'range', [min_value max_value] (scaling used for display)
%                'colormap', 'gray' (colour map used for display)
%
% Written by: Rob Bradley, (c) 2015

img_tmp = img(:,:,1);
p = inputParser;
%p.addOptional('range', [min(img_tmp(:)) max(img_tmp(:))], @(x) isnumeric(x) & numel(x)>1);
p.addOptional('range', 'auto', @(x) isnumeric(x) & numel(x)>1);
p.addOptional('colormap', 'gray')
p.addOptional('fig', []);
p.addOptional('axes', []);
p.addOptional('loadfcn', []);
p.addOptional('updatefcn', [], @(x) iscell(x));
p.addOptional('name', []);
p.parse(varargin{:});

%p.Results


if isempty(p.Results.fig)      
    
    if isempty(p.Results.axes)
        fig = figure('Name', inputname(1), 'Color', [0 0 0], 'Tag', 'imager', 'NumberTitle', 'off');    
    else
        fig = get(p.Results.axes, 'parent');
    end
else
    D = getappdata(p.Results.fig, 'imager');
    if ~isempty(D)
        D.img = img;
        setappdata(p.Results.fig, 'imager', D);
        fig = p.Results.fig;
        reslice([], [],[]);
        return;
    end  
    fig = p.Results.fig;
end  

if ~isempty(p.Results.name)
    set(fig, 'Name', p.Results.name);
end

pos = get(fig, 'Position');
pos(3) = pos(4)*size(img,2)/size(img,1);
apr = size(img,2)/size(img,1);
if ~isempty(p.Results.axes)
   a = p.Results.axes;   
else
    set(fig, 'Position', pos);
    a = axes('Units','normalized', 'Position', [0 0 1 1], 'Parent', fig);
end
handles.c = eval([p.Results.colormap '(256)']);

%Show 1st image
img_tmp = img(:,:,1); 
d_range = p.Results.range;
if ischar(p.Results.range)
    curr_min = min(img_tmp(:));
    curr_max = max(img_tmp(:));
else
    curr_min = p.Results.range(1);
    curr_max = p.Results.range(2);
end
img_tmp(img_tmp<curr_min) = curr_min;
img_tmp(img_tmp>curr_max) = curr_max;


img_handle = image(img_tmp, 'CDataMapping', 'scaled', 'parent', a);
set(a, 'Visible', 'off');
img_handle = [img_handle fig];
colormap(handles.c);
handles.c = uint8(255*handles.c);

if ndims(img)>2
    multiple_imgs = 1;
    no_of_imgs = size(img,3);
    call_load = 0;
    cmap= zeros(size(img,1), size(img,2),3, 'uint8');
elseif ~isempty(p.Results.loadfcn)   
    multiple_imgs = 1;
    no_of_imgs = p.Results.loadfcn{2};
    call_load = 1;
    cmap= zeros(size(img,1), size(img,2),3, 'uint8');
elseif strcmpi(class(img), 'DATA3D')    
    no_of_imgs = img.dimensions(3);
    if no_of_imgs>1
        multiple_imgs = 1;
    else
        multiple_imgs = 0;
    end
    call_load = 0;
    cmap= zeros(img.dimensions(1), img.dimensions(2),3, 'uint8');
    
else
    multiple_imgs = 0;
    call_load = 0;
    cmap= zeros(size(img,1), size(img,2),3, 'uint8');
end    


handles.scrollbar =[];
if multiple_imgs
   
    %Create scroll bar
    handles.scrollbar =  javax.swing.JScrollBar(0, 1, 10, 1, 10*no_of_imgs+1);
    handles.scrollbar.setPreferredSize(java.awt.Dimension(50,16));
    handles.scrollbar.setUnitIncrement(10);
    try
        set(handles.scrollbar, 'Interruptible', 'off', 'BusyAction', 'cancel');
        set(handles.scrollbar, 'AdjustmentValueChangedCallback', @reslice);
        
        
    catch
        %2014a onwards behaviour
        handles.scrollbar = handle(handles.scrollbar, 'CallbackProperties');
        set(handles.scrollbar, 'AdjustmentValueChangedCallback', @reslice)
        
    end
    
    
    %Create labels
    handles.slicelabel = javax.swing.JLabel(sprintf('%6d',1));
    sz = handles.slicelabel.getFontMetrics(handles.slicelabel.getFont).stringWidth(sprintf('%5d',88888));
    handles.slicelabel.setPreferredSize(java.awt.Dimension(sz, 26));
    handles.slicelabel.setMaximumSize(java.awt.Dimension(sz, 26));
    handles.slicelabel.setMinimumSize(java.awt.Dimension(sz, 26));   
    
    sliceno  = com.mathworks.mwswing.MJLabel('Image:');
    sliceno.setHorizontalAlignment(0);
    sz = sliceno.getFontMetrics(sliceno.getFont).stringWidth('mmmmmm');
    sliceno.setPreferredSize(java.awt.Dimension(sz, 26));
    sliceno.setMaximumSize(java.awt.Dimension(sz, 26));
    sliceno.setMinimumSize(java.awt.Dimension(sz, 26));
    
    %create toolbar
    toolbar = uitoolbar('Parent', fig);
    drawnow;    
    jtoolbar = get(toolbar, 'JavaContainer');
    jcompeer = get(jtoolbar, 'ComponentPeer');
    jcompeer.add(sliceno, java.awt.BorderLayout.LINE_START);
    jcompeer.add(handles.scrollbar,  java.awt.BorderLayout.CENTER);
    jcompeer.add(handles.slicelabel,  java.awt.BorderLayout.LINE_END);
          
end

hcmenu = uicontextmenu;
item1 = uimenu(hcmenu, 'Label', 'Set display range', 'Callback', @setrange);
set(img_handle, 'UIContextMenu', hcmenu);

set(fig, 'ResizeFcn', @resize_update);
D.p = p;
D.img = img;
D.handles = handles;
D.call_load = call_load;
D.d_range = d_range;
D.cmap = cmap;
D.img_handle = img_handle;
setappdata(fig, 'imager', D);
reslice([],[],[]); 

    function reslice(hObject, eventdata, view)
        
        tic
        
        try
            if get(hObject, 'ValueIsAdjusting')
                
                return;
            end
        catch
        end
        set(hObject,'ValueIsAdjusting',1)
        D = getappdata(fig, 'imager');
        handles = D.handles;
        img = D.img;
        p = D.p;
        call_load = D.call_load;
        d_range = D.d_range;
        cmap = D.cmap;
        img_handle = D.img_handle;
        
        %Calculate image number
        if ~isempty(handles.scrollbar)
            img_no = round((1+(handles.scrollbar.getValue-1)/10));
            set(handles.slicelabel, 'Text', sprintf('%6d',img_no));
        else
            img_no = 1;
        end
           
        %Display image
        if call_load
            img_tmp = p.Results.loadfcn{1}(img_no);
           if ~isempty(p.Results.loadfcn{3})
                img_tmp = img_tmp./p.Results.loadfcn{3};
           end    
           %img_tmp = double(img_tmp);
           
        else  
            img_tmp = double(img(:,:,img_no));
        end
        img_tmp(isinf(img_tmp)) = NaN;
        
        if ischar(d_range)
            %d_range
            curr_min = min(img_tmp(:));
            curr_max = max(img_tmp(:));        
        else
            curr_min = d_range(1);
            curr_max = d_range(2);
        end
        if curr_max==curr_min
           curr_max = curr_min+1e-6; 
        end
        %tic
        img_tmp(isnan(img_tmp)) = curr_max;
        img_tmp = floor(256*(img_tmp(:)-curr_min)/(curr_max-curr_min));
        img_tmp(img_tmp>256)=256;
        img_tmp(img_tmp<1)=1;
       
        cmap(:) = handles.c(img_tmp,:);
        set(img_handle(1), 'CData', cmap);
        
        if ~isempty(p.Results.updatefcn)
           
            feval(p.Results.updatefcn{1}, img_no);
            
        end
        
        toc
        set(hObject,'ValueIsAdjusting',1)
    end


    function setrange(~,~)
       
        if ischar(d_range)
            minval = ['auto (' num2str(curr_min) ')'];
            maxval = ['auto (' num2str(curr_max) ')'];
        else
            minval = num2str(d_range(1));
            maxval = num2str(d_range(2));
        end
        answer = inputdlg({'Range minimum:','Range maximum:'},'Enter display range',1,{minval, maxval});
        
        if ~isempty(answer)
            strfind(answer{1}, 'auto')
            strfind(answer{2}, 'auto')
           if isempty(strfind(answer{1}, 'auto')) & isempty(strfind(answer{2}, 'auto'));
                d_range = str2num(answer{1}); 
                d_range(2) = str2num(answer{2}); 
           else
               d_range = 'auto';
           end
        end
        D = getappdata(fig, 'imager');
        D.d_range = d_range;
        setappdata(fig, 'imager', D);
        %d_range
        %pause
        reslice([],[],[]);
    end



    function resize_update(~,~)
        
        
        return;
        newPos = get(fig,'Pos'); % Get new
        sizeChg = abs(newPos(3:4)-pos(3:4)); % Change in
        if sizeChg(1) >= sizeChg(2)
           newPos(3:4) = [newPos(3) newPos(3)/apr];
        else
           newPos(3:4) = [newPos(4)*apr newPos(4)];
        end

        set(fig,'Pos',newPos); % Set new
        findfigs; % Reposition figure if it goes off screen 
    end
end
