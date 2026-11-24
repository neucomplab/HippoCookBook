function entry = indexNewSession(varargin)
% entry = indexNewSession(varargin)
%   Index a session in the lab session database: one JSON file per session
%   in a shared folder on the NAS (default: <neural>/indexedSessions/).
%   Re-indexing a session overwrites its file (no duplicates possible).
%
% INPUTS (name-value)
%   basepath              Session folder (default: pwd)
%   project               Project(s) of the session, char ('ReactInh
%                         Bibliocampus') or cell. Default: session.general.projects
%   index_path            Folder with the per-session JSON files
%                         (default: nas_path('neural')/indexedSessions)
%   nas_list              NAS names used to locate the session (default: {'neural','neural3'})
%   removeDatFiles        Remove _original/_temp .dat, amplifier*.dat in
%                         subfolders and Kilosort .phy (default: false)
%   copyFiles             Copy session to driveStorage_location and remove
%                         the local folder (default: false)
%   driveStorage_location NAS where to copy the session if copyFiles (default: 'neural')
%
% OUTPUT
%   entry                 Struct written to <index_path>/<sessionName>.json
%
% Fields: SessionName, Subject, Path (relative to the NAS root), Location
% (NAS name), Strain, GeneticLine, Optogenetics {list}, Behavior {list},
% numCells, brainRegions {list}, Project {list}, indexedDate, updatedDate,
% indexedBy.
%
% MV 2022, 2026: one JSON per session on the NAS (no CSV, no git)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Defaults and Params
p = inputParser;
p.KeepUnmatched = true; % old calls may still pass CSV/git parameters
addParameter(p,'basepath',pwd,@isfolder);
addParameter(p,'project',[],@(x) isempty(x) || ischar(x) || isstring(x) || iscell(x));
addParameter(p,'index_path',[],@(x) isempty(x) || ischar(x) || isstring(x));
addParameter(p,'nas_list',{'neural','neural3'},@iscell);
addParameter(p,'removeDatFiles',false,@islogical);
addParameter(p,'copyFiles',false,@islogical);
addParameter(p,'driveStorage_location','neural',@(x) ischar(x) || isstring(x));

parse(p,varargin{:});

basepath = char(p.Results.basepath);
project = p.Results.project;
index_path = char(p.Results.index_path);
nas_list = p.Results.nas_list;
removeDatFiles = p.Results.removeDatFiles;
copyFiles = p.Results.copyFiles;
driveStorage_location = lower(char(p.Results.driveStorage_location));

obsolete = fieldnames(p.Unmatched);
if ~isempty(obsolete)
    warning('indexNewSession: ignoring obsolete parameter(s): %s (the CSV/git index is no longer used).', strjoin(obsolete, ', '));
end

if isempty(index_path)
    index_path = fullfile(nas_path('neural'), 'indexedSessions');
end
if ~isfolder(index_path)
    error('Index folder not found: %s. Check that the NAS is mounted (nas_path) or pass ''index_path''.', index_path);
end

%% Session metadata
basepath = regexprep(basepath, '[\\/]+$', ''); % remove trailing separators
if ~copyFiles && isempty(findNasLocation(basepath, nas_list))
    error(['Session is not on any NAS (%s): %s\n' ...
        'Move it to a NAS or use ''copyFiles'', true.'], strjoin(nas_list, ', '), basepath);
end
session = loadSession(basepath);
sessionName = lower(session.general.name);
subject = session.animal.name;

% Where will the session live? Checked BEFORE removing or moving anything
if copyFiles
    storage_root = nas_path(driveStorage_location);
    if isempty(storage_root)
        error('Unknown driveStorage_location: %s', driveStorage_location);
    end
    final_basepath = fullfile(storage_root, subject, session.general.name);
    location = driveStorage_location;
    relPath = [subject '/' session.general.name];
else
    final_basepath = basepath;
    [location, relPath] = findNasLocation(basepath, nas_list);
    if isempty(location)
        error(['Session is not on any NAS (%s): %s\n' ...
            'Move it to a NAS or use ''copyFiles'', true.'], strjoin(nas_list, ', '), basepath);
    end
end

% Project
if isempty(project)
    project = session.general.projects;
end
projectList = toList(project);

% Optogenetics
optogenetics = {};
layout = '';
if isfield(session,'extracellular') && isfield(session.extracellular,'chanCoords') && isfield(session.extracellular.chanCoords,'layout')
    layout = session.extracellular.chanCoords.layout;
end
switch layout
    case {'uLED-12LED-32Ch-4Shanks', 'DiagnosticBiochip-128-6-128ch&uLED_12LED-32Ch-4Shanks'}
        optogenetics = {layout};
    case {'BehnkeFried-8ch.csv', 'A8x8-Edge-5mm-50-150-177'}
        optogenetics = {};
    otherwise
        if isfield(session.animal,'opticFiberImplants')
            for ii = 1:length(session.animal.opticFiberImplants)
                if isfield(session.animal.opticFiberImplants{ii},'opticFiber')
                    optogenetics{end+1} = lower(session.animal.opticFiberImplants{ii}.opticFiber);
                end
            end
        end
end

% Behavior (environments of the maze epochs)
behavior = {};
if isfield(session,'epochs')
    for ii = 1:length(session.epochs)
        ep = session.epochs{ii};
        if isfield(ep,'behavioralParadigm') && contains(ep.behavioralParadigm,'Maze') && isfield(ep,'environment')
            behavior{end+1} = lower(ep.environment);
        end
    end
end
behavior = unique(behavior, 'stable');

% Brain regions
brainRegions = {};
if isfield(session,'brainRegions') && isstruct(session.brainRegions)
    brainRegions = fieldnames(session.brainRegions)';
end

% Number of cells
cd(basepath);
try
    spikes = loadSpikes;
    numCells = spikes.numcells;
catch
    warning('No spikes found for %s. numCells set to 0.', sessionName);
    numCells = 0;
end

%% Entry
entry = struct();
entry.SessionName  = sessionName;
entry.Subject      = lower(subject);
entry.Path         = relPath;  % case preserved (case-sensitive on Mac)
entry.Location     = location;
entry.Strain       = lower(session.animal.strain);
entry.GeneticLine  = lower(session.animal.geneticLine);
entry.Optogenetics = optogenetics;
entry.Behavior     = behavior;
entry.numCells     = numCells;
entry.brainRegions = brainRegions;
entry.Project      = projectList;

%% Removing dat files before copying files to storage
if removeDatFiles
    % Remove _original and _temp .dat
    if ~isempty(dir([session.general.name,'_original.dat']))
        delete([session.general.name,'_original.dat']);
    end
    if ~isempty(dir([session.general.name,'_temp.dat']))
        delete([session.general.name,'_temp.dat']);
    end

    % Remove amplifier*.dat in subfolders
    if ~isempty(dir([session.general.name,'.MergePoints.events.mat']))
        file = dir([session.general.name,'.MergePoints.events.mat']);
        load(file.name)

        for i = 1:length(MergePoints.foldernames)
            try
                cd(MergePoints.foldernames{i})
                if ~isempty(dir('amplifier*.dat'))
                    file = dir('amplifier*.dat');
                    delete(file.name);
                end
                cd(basepath)
            catch
                warning('Problem removing session folders...');
            end
        end
    end

    % Remove kilosort .phy
    if ~isempty(dir('Kilosort*'))
        file = dir('Kilosort*');
        cd(file(end).name);
        try
            if exist('.phy','dir')
                rmdir('.phy','s');
            end
        catch
            warning('.phy folder does not exist... Maybe was removed before?');
        end
        cd(basepath);
    end
end

%% Copying files to storage
if copyFiles
    if ~exist(fileparts(final_basepath),'dir')
        mkdir(fileparts(final_basepath));
    end
    success = copyfile(basepath, final_basepath);
    if ~success
        error('Copy to %s failed. Session NOT indexed.', final_basepath);
    end
    cd(final_basepath);
    try
        rmdir(basepath,'s');
    catch
        warning('The local session folder could not be removed!');
    end
end

%% Write index file (only once the session is in its final place)
target = fullfile(index_path, [sessionName '.json']);
now_str = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
entry.indexedDate = now_str;
if isfile(target)
    try
        old = jsondecode(fileread(target));
        if isfield(old,'indexedDate')
            entry.indexedDate = old.indexedDate;
        end
    catch
    end
    action = 'Updated';
else
    action = 'Indexed';
end
entry.updatedDate = now_str;
entry.indexedBy = char(getenv('USERNAME'));
if isempty(entry.indexedBy)
    entry.indexedBy = char(getenv('USER'));
end

% write to a temporary file and rename, so a crash never leaves a half file
tmp = [target '.tmp'];
fid = fopen(tmp, 'w', 'n', 'UTF-8');
if fid < 0
    error('Could not write %s', tmp);
end
fprintf(fid, '%s', jsonencode(entry, 'PrettyPrint', true));
fclose(fid);
movefile(tmp, target, 'f');

fprintf('%s %s (%s: %s)\n', action, sessionName, location, relPath);

end

%% ------------------------------------------------------------------------
function [location, relPath] = findNasLocation(basepath, nas_list)
% Which NAS contains basepath, and the path relative to its root
location = '';
relPath = '';
for ii = 1:length(nas_list)
    root = nas_path(nas_list{ii});
    if isempty(root)
        continue
    end
    root = regexprep(root, '[\\/]+$', '');
    n = length(root);
    % root must be followed by a separator ('/Volumes/NEURAL' ~= '/Volumes/NEURAL3')
    if length(basepath) > n + 1 && strcmpi(basepath(1:n), root) && any(basepath(n+1) == '\/')
        location = lower(nas_list{ii});
        relPath = strrep(basepath(n+2:end), '\', '/');
        return
    end
end
end

function list = toList(x)
% char ('a b, c'), string or cell -> row cell of non-empty char
if isempty(x)
    list = {};
    return
end
if iscell(x)
    x = strjoin(cellfun(@char, x, 'UniformOutput', false), ' ');
end
list = strsplit(strtrim(char(x)), {' ', ',', ';'});
list = list(~cellfun(@isempty, list));
end
