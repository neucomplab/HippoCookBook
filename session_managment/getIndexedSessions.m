function sessionsTable = getIndexedSessions(varargin)
% sessionsTable = getIndexedSessions(varargin)
%   Read the lab session index (one JSON file per session, written by
%   indexNewSession) and return it as a table, one row per session.
%
% INPUTS (name-value)
%   index_path   Folder with the per-session JSON files
%                (default: nas_path('neural')/indexedSessions)
%
% OUTPUT
%   sessionsTable  Table with the fields of indexNewSession, plus:
%                  basepath  full path to the session on this computer
%                            (nas_path(Location) + Path)
%   List fields (Optogenetics, Behavior, brainRegions, Project) are cells
%   of char, e.g. sessionsTable.Project{3} = {'Bibliocampus','ReactInh'}.
%
% MV 2026
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Defaults and Params
p = inputParser;
addParameter(p,'index_path',[],@(x) isempty(x) || ischar(x) || isstring(x));
parse(p,varargin{:});
index_path = char(p.Results.index_path);

if isempty(index_path)
    index_path = fullfile(nas_path('neural'), 'indexedSessions');
end
if ~isfolder(index_path)
    error('Index folder not found: %s. Check that the NAS is mounted (nas_path) or pass ''index_path''.', index_path);
end

%% Read files
textFields = {'SessionName','Subject','Path','Location','Strain','GeneticLine','indexedDate','updatedDate','indexedBy'};
listFields = {'Optogenetics','Behavior','brainRegions','Project'};
fieldOrder = [textFields(1:6), listFields(1:2), {'numCells'}, listFields(3:4), textFields(7:9)];

files = dir(fullfile(index_path, '*.json'));
entries = cell(length(files),1);
keep = false(length(files),1);
for ii = 1:length(files)
    try
        e = jsondecode(fileread(fullfile(files(ii).folder, files(ii).name)));
    catch ME
        warning('Skipping %s (could not read it: %s)', files(ii).name, ME.message);
        continue
    end

    % normalize: every entry has the same fields and types
    s = struct();
    for jj = 1:length(textFields)
        if isfield(e, textFields{jj}) && ~isempty(e.(textFields{jj}))
            s.(textFields{jj}) = char(e.(textFields{jj}));
        else
            s.(textFields{jj}) = '';
        end
    end
    for jj = 1:length(listFields)
        if isfield(e, listFields{jj})
            s.(listFields{jj}) = toRowCell(e.(listFields{jj}));
        else
            s.(listFields{jj}) = {};
        end
    end
    if isfield(e,'numCells') && ~isempty(e.numCells)
        s.numCells = double(e.numCells);
    else
        s.numCells = NaN;
    end

    [~, fileName] = fileparts(files(ii).name);
    if ~strcmpi(s.SessionName, fileName)
        warning('%s: SessionName inside the file is "%s"', files(ii).name, s.SessionName);
    end

    entries{ii} = orderfields(s, fieldOrder);
    keep(ii) = true;
end
entries = [entries{keep}];

if isempty(entries)
    warning('No sessions found in %s', index_path);
    sessionsTable = table();
    return
end

%% Table (built column by column: struct2table would unwrap one-element lists)
sessionsTable = table();
for jj = 1:length(fieldOrder)
    if strcmp(fieldOrder{jj}, 'numCells')
        sessionsTable.numCells = [entries.numCells]';
    else
        sessionsTable.(fieldOrder{jj}) = {entries.(fieldOrder{jj})}';
    end
end
sessionsTable = sortrows(sessionsTable, 'SessionName');

% full path on this computer
basepath = cell(height(sessionsTable),1);
for ii = 1:height(sessionsTable)
    root = nas_path(sessionsTable.Location{ii});
    if isempty(root)
        basepath{ii} = '';
    else
        basepath{ii} = adapt_filesep([root filesep sessionsTable.Path{ii}]);
    end
end
sessionsTable.basepath = basepath;

end

%% ------------------------------------------------------------------------
function c = toRowCell(x)
% jsondecode gives a column cell for ["a","b"], a char for "a" and [] for []
if isempty(x)
    c = {};
elseif iscell(x)
    c = cellfun(@char, x(:)', 'UniformOutput', false);
else
    c = {char(x)};
end
end
