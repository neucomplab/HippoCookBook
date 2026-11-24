function [projectResults, projectSessionResults] =  loadProjectResults(varargin)
% [projectResults, projectSessionResults] =  loadProjectResults(varargin)
%   Load and stack all results for a group of indexed sessions.
%   Sessions are selected from the lab index (getIndexedSessions) by
%   project, behavior, brain regions and/or session names.
%
% INPUTS (name-value)
%   project               Project(s), char or cell. A session is selected if
%                         it belongs to ANY of them. 'All' = no filter.
%   behavior              Behavior(s), char or cell (e.g. 'tmaze'). ANY of them.
%   brainRegions          Region(s), char or cell. Matches the beginning of
%                         the region name: 'CA1' selects CA1sp, CA1so...
%   list_of_sessions      Cell with session names, or 'all'. Keeps this order.
%   list_of_paths         Cell with session folders. Skips the index entirely.
%   index_path            Folder of the session index (default: getIndexedSessions default)
%   analysis_project_path Folder for the .mat and the summaries (default: pwd)
%   results               Cell with the results to load, REPLACES the default
%                         list (e.g. {'ripples_psth','ACGPeak'}). Default: list below
%   add_results           Cell with extra result names added to the list
%   keepSessionResults    Keep per-session copies of the results in
%                         projectSessionResults (default: false: saves
%                         memory, only the stacked results are kept).
%   includeSpikes         Keep spikes per session (default: true)
%   includeLFP            Keep LFP per session (default: false, ignored if lightVersion)
%   lightVersion          Remove spike times and rasters (default: true)
%   before_after          Also load cell_metrics_before/after (default: false)
%   openCellExplorer      Open CellExplorer on the batch, close it to go on (default: true).
%                         It adds fields to cell_metrics (normalized ACGs,
%                         z-scored waveforms, thetaPhase_zscored, labels, tags...)
%   loadLast              Load the last saved .mat of this project instead (default: false)
%   saveMat               Save results in analysis_project_path (default: true)
%   saveSummaries         Copy SummaryFigures/Summary*.png (default: true)
%   save_as               Name of the .mat (default: yyyy-mm-dd_<project>)
%
% OUTPUTS
%   projectResults        Results stacked across sessions, one row per cell,
%                         plus session/geneticLine/expSubject per cell,
%                         sessionsTable (index rows of the loaded sessions)
%                         and resultsFound (sessions x results, true if found)
%   projectSessionResults Results per session (cells of length nSessions)
%
% EXAMPLES
%   [pr, psr] = loadProjectResults('project','Crabcer','behavior','tmaze',...
%       'analysis_project_path','Y:\Analysis\Crabcer');
%   [pr, psr] = loadProjectResults('list_of_sessions',{'cancer2_250702_sess1','cancer2_250703_sess2'},...
%       'saveMat',false,'saveSummaries',false);
%
% MV 2022, 2025, 2026 (session index from getIndexedSessions)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Defaults and Parms
isText = @(x) isempty(x) || ischar(x) || isstring(x) || iscell(x);
p = inputParser;
p.KeepUnmatched = true; % old calls may pass indexedSessionCSV_path/name
addParameter(p,'project','Undefined',isText);
addParameter(p,'behavior',[],isText);
addParameter(p,'brainRegions',[],isText);
addParameter(p,'list_of_sessions',[],isText);
addParameter(p,'list_of_paths',[],@(x) isempty(x) || iscell(x));
addParameter(p,'index_path',[],@(x) isempty(x) || ischar(x) || isstring(x));
addParameter(p,'analysis_project_path',[],@(x) isempty(x) || isfolder(x));
addParameter(p,'results',[],@(x) isempty(x) || iscell(x) || ischar(x));
addParameter(p,'add_results',[],@(x) isempty(x) || iscell(x) || ischar(x));
addParameter(p,'keepSessionResults',false,@islogical);
addParameter(p,'includeSpikes',true,@islogical);
addParameter(p,'includeLFP',false,@islogical);
addParameter(p,'lightVersion',true,@islogical);
addParameter(p,'before_after',false,@islogical);
addParameter(p,'openCellExplorer',true,@islogical);
addParameter(p,'loadLast',false,@islogical);
addParameter(p,'saveMat',true,@islogical);
addParameter(p,'saveSummaries',true,@islogical);
addParameter(p,'save_as',[],@(x) isempty(x) || ischar(x));

parse(p,varargin{:});

project = toList(p.Results.project);
behavior = toList(p.Results.behavior);
brainRegions = toList(p.Results.brainRegions);
list_of_sessions = p.Results.list_of_sessions;
list_of_paths = p.Results.list_of_paths;
index_path = p.Results.index_path;
analysis_project_path = p.Results.analysis_project_path;
results = p.Results.results;
add_results = p.Results.add_results;
keepSessionResults = p.Results.keepSessionResults;
includeSpikes = p.Results.includeSpikes;
includeLFP = p.Results.includeLFP;
lightVersion = p.Results.lightVersion;
before_after = p.Results.before_after;
openCellExplorer = p.Results.openCellExplorer;
loadLast = p.Results.loadLast;
saveMat = p.Results.saveMat;
saveSummaries = p.Results.saveSummaries;
save_as = p.Results.save_as;

obsolete = fieldnames(p.Unmatched);
if ~isempty(obsolete)
    warning('loadProjectResults: ignoring obsolete parameter(s): %s (sessions now come from getIndexedSessions).', strjoin(obsolete, ', '));
end

if any(strcmpi(project, {'Undefined','All'}))
    project = {};
end
projectName = strjoin(project, '_');
if isempty(projectName)
    projectName = 'sessions';
end

if isempty(analysis_project_path)
    analysis_project_path = pwd;
    if saveMat || saveSummaries || loadLast
        fprintf('analysis_project_path not provided. Using %s\n', analysis_project_path);
    end
end

% go back to the starting folder when done (the loop cd's into each session)
startFolder = pwd;
cleanupObj = onCleanup(@() cd(startFolder));

if isempty(save_as)
    save_as = [char(datetime('now','Format','yyyy-MM-dd')) '_' projectName];
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% By default it loads the following results:
% {...
% 'optogeneticResponse',       ...
% 'ripples_psth,               ...
% 'slowOscillations_psth',     ...
% 'theta_*.PhaseLockingData',  ...
% 'lgamma*.PhaseLockingData',  ...
% 'hgamma*.PhaseLockingData',  ...
% 'ripple*.PhaseLockingData',  ...
% 'spatialModulation',         ...
% 'placeFields',               ...
% 'behavior.cellinfo',         ...
% 'ACGPeak',                   ...
% }
%
% Some results previusly used in addition:
% {...
% 'averageCCG',                ... (60-100 MB per session: load only if needed)
% 'speedCorr',                 ...
% 'uLEDResponse.cellinfo',     ...
% 'spikeCCGchange',            ...
% 'fiber_psth_ripples',        ...
% 'FiberPhotometry',           ...
% 'behavior_fiber',            ...
% }; % etc
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Load previous results
if loadLast
    projectFiles = dir(fullfile(analysis_project_path, ['*' projectName '.mat']));
    if ~isempty(projectFiles)
        [~, last] = max([projectFiles.datenum]);
        fprintf('Loading %s...\n', projectFiles(last).name);
        load(fullfile(projectFiles(last).folder, projectFiles(last).name), 'projectResults', 'projectSessionResults');
        return
    else
        warning('Not possible to reload project. Loading data from sessions...');
    end
end

%% List of results
if isempty(results)
    list_of_results = {'optogeneticResponse','ripples_psth','slowOscillations_psth','theta_*.PhaseLockingData','lgamma*.PhaseLockingData','hgamma*.PhaseLockingData','ripple*.PhaseLockingData',...
            'spatialModulation','placeFields','behavior.cellinfo','ACGPeak'};
elseif ischar(results)
    list_of_results = {results};
else
    list_of_results = results(:)';
end
if ischar(add_results)
    add_results = {add_results};
end
list_of_results = unique([list_of_results, add_results(:)'], 'stable');
% field names for each result ('theta_*.PhaseLockingData' -> 'theta_PhaseLockingData')
result_fields = replace(list_of_results, {'.','*'}, '');
result_fields = replace(result_fields, '-', '_');

%% Select sessions
if ~isempty(list_of_paths)
    sessions_basepaths = list_of_paths(:)';
    sessionsTable = table();
else
    sessionsTable = getIndexedSessions('index_path', index_path);
    selected = true(height(sessionsTable),1);

    if ~isempty(project)
        selected = selected & cellfun(@(x) any(ismember(lower(x), lower(project))), sessionsTable.Project);
    end
    if ~isempty(behavior)
        selected = selected & cellfun(@(x) any(ismember(lower(x), lower(behavior))), sessionsTable.Behavior);
    end
    if ~isempty(brainRegions)
        selected = selected & cellfun(@(x) any(startsWith(lower(x), lower(brainRegions))), sessionsTable.brainRegions);
    end

    loadAll = (ischar(list_of_sessions) || isstring(list_of_sessions)) && strcmpi(list_of_sessions, 'all');
    if ~isempty(list_of_sessions) && ~loadAll
        list_of_sessions = lower(toList(list_of_sessions));
        [found, idx] = ismember(list_of_sessions, lower(sessionsTable.SessionName));
        if ~all(found)
            error('Sessions not found in the index: %s', strjoin(list_of_sessions(~found), ', '));
        end
        notMatching = idx(~selected(idx));
        if ~isempty(notMatching)
            error('Sessions do not match the project/behavior/brainRegions filters: %s', ...
                strjoin(sessionsTable.SessionName(notMatching), ', '));
        end
        order = idx; % keep the order given by the user
    else
        if isempty(project) && isempty(behavior) && isempty(brainRegions) && ~loadAll
            error('No sessions selected. Give project, behavior, brainRegions or list_of_sessions (''all'' loads the whole index).');
        end
        order = find(selected);
    end

    if isempty(order)
        error('No indexed sessions match project: %s | behavior: %s | brainRegions: %s', ...
            strjoin(project, ' '), strjoin(behavior, ' '), strjoin(brainRegions, ' '));
    end
    sessionsTable = sessionsTable(order,:);
    sessions_basepaths = sessionsTable.basepath';
end

missing = ~cellfun(@isfolder, sessions_basepaths);
if any(missing)
    error('Session folders not found (is the NAS mounted?): %s', strjoin(sessions_basepaths(missing), ', '));
end

fprintf('Loading %i sessions... \n', length(sessions_basepaths));

%% load cellexplorer results
cell_metrics = loadBatch('basepaths', sessions_basepaths);
if openCellExplorer
    disp('Close CellExplorer to continue...');
    cell_metrics = CellExplorer('metrics', cell_metrics);
end

if before_after
    cell_metrics_before = loadBatch('basepaths', sessions_basepaths, 'saveAs', 'cell_metrics_before');
    cell_metrics_after = loadBatch('basepaths', sessions_basepaths, 'saveAs', 'cell_metrics_after');
    if openCellExplorer
        disp('Close CellExplorer to continue (before)...');
        cell_metrics_before = CellExplorer('metrics', cell_metrics_before);
        disp('Close CellExplorer to continue (after)...');
        cell_metrics_after = CellExplorer('metrics', cell_metrics_after);
    end
end

%% collect data per session
if saveSummaries
    saveSummariespath = fullfile(analysis_project_path, 'Summaries');
    if ~exist(saveSummariespath, 'dir')
        mkdir(saveSummariespath);
    end
end

if lightVersion
    includeLFP = false;
end

nSessions = length(sessions_basepaths);
resultsFound = false(nSessions, length(list_of_results));
multipleFiles = {};
projectSessionResults = [];
for ii = 1:nSessions
    fprintf(' > %3.i/%3.i sessions \n', ii, nSessions);
    cd(sessions_basepaths{ii});

    % get some useful fields
    spikes = loadSpikes;
    projectSessionResults.numcells(ii) = spikes.numcells;

    % per-cell fields are built from spikes.numcells: it must match cell_metrics
    nCellMetrics = sum(cell_metrics.batchIDs == ii);
    if nCellMetrics ~= spikes.numcells
        error(['%s: %d cells in spikes but %d in cell_metrics. Results would be misaligned.\n' ...
            'Re-run ProcessCellMetrics for this session (or check its spikes.cellinfo.mat).'], ...
            sessions_basepaths{ii}, spikes.numcells, nCellMetrics);
    end

    session = loadSession;
    if keepSessionResults
        projectSessionResults.cell_metrics{ii} = loadCellMetrics;
    end
    projectSessionResults.session{ii} = session;
    projectSessionResults.sessionName{ii} = session.general.name;
    projectSessionResults.geneticLine{ii} = session.animal.geneticLine;
    projectSessionResults.expSubject{ii} = session.animal.name;
    clear session

    % spikes
    if includeSpikes
        if lightVersion
            spikes = rmfield(spikes, intersect({'ts','ids','amplitudes'}, fieldnames(spikes)));
        end
        projectSessionResults.spikes{ii} = spikes;
    end
    clear spikes

    % loop results
    for jj = 1:length(list_of_results)
        targetFile = dir(['*.' list_of_results{jj} '*.mat']);
        if isempty(targetFile)
            projectSessionResults.(result_fields{jj}){ii} = NaN;
        else
            if length(targetFile) > 1
                multipleFiles{end+1} = sprintf('%s: %s matches %s (loaded %s)', projectSessionResults.sessionName{ii}, ...
                    list_of_results{jj}, strjoin({targetFile.name}, ', '), targetFile(1).name);
            end
            projectSessionResults.(result_fields{jj}){ii} = importdata(targetFile(1).name);
            resultsFound(ii,jj) = true;
        end
    end

    % old optogeneticResponse files have no checkedCells
    if isfield(projectSessionResults,'optogeneticResponse') && isstruct(projectSessionResults.optogeneticResponse{ii}) ...
            && ~isfield(projectSessionResults.optogeneticResponse{ii},'checkedCells') ...
            && isfield(projectSessionResults.optogeneticResponse{ii},'bootsTrapRate')
        projectSessionResults.optogeneticResponse{ii}.checkedCells = zeros(size(projectSessionResults.optogeneticResponse{ii}.bootsTrapRate,1),1);
    end

    if lightVersion
        for removeRasterFrom = {'optogeneticResponse', 'ripples_psth', 'slowOscillations_psth'}
            fld = removeRasterFrom{1};
            if isfield(projectSessionResults, fld) && isstruct(projectSessionResults.(fld){ii}) ...
                    && isfield(projectSessionResults.(fld){ii}, 'raster')
                projectSessionResults.(fld){ii} = rmfield(projectSessionResults.(fld){ii}, 'raster');
            end
        end
    end

    if includeLFP
        projectSessionResults.lfp{ii} = getLFP;
    end

    if saveSummaries
        summaryPngs = dir(fullfile(sessions_basepaths{ii}, 'SummaryFigures', 'Summary*.png'));
        for jj = 1:length(summaryPngs)
            copyfile(fullfile(summaryPngs(jj).folder, summaryPngs(jj).name),...
                fullfile(saveSummariespath, [projectSessionResults.sessionName{ii} '_' summaryPngs(jj).name]));
        end
    end
end
cd(startFolder);

%% summary of results not found / ambiguous
for jj = 1:length(list_of_results)
    nMissing = sum(~resultsFound(:,jj));
    if nMissing == nSessions
        fprintf('  %-26s not found in any session\n', result_fields{jj});
    elseif nMissing > 0
        fprintf('  %-26s missing in %d/%d sessions: %s\n', result_fields{jj}, nMissing, nSessions, ...
            strjoin(projectSessionResults.sessionName(~resultsFound(:,jj)), ', '));
    end
end
if ~isempty(multipleFiles)
    warning('Several files match the same result (the first one was loaded):\n  %s', strjoin(multipleFiles, '\n  '));
end

%% stack all results
projectResults = struct();
for ii = 1:length(result_fields)
    if any(resultsFound(:,ii))
        try
            projectResults.(result_fields{ii}) = stackSessionResult(projectSessionResults.(result_fields{ii}), projectSessionResults.numcells);
        catch ME
            warning('%s was not stacked: %s', result_fields{ii}, ME.message);
        end
    end
    if ~keepSessionResults
        projectSessionResults = rmfield(projectSessionResults, result_fields{ii});
    end
end
projectResults.resultsFound = array2table(resultsFound, 'VariableNames', result_fields, ...
    'RowNames', matlab.lang.makeUniqueStrings(projectSessionResults.sessionName));

projectResults.cell_metrics = cell_metrics;
if before_after
    projectResults.cell_metrics_before = cell_metrics_before;
    projectResults.cell_metrics_after = cell_metrics_after;
end
projectResults.sessionsTable = sessionsTable;

% session, genetic line, experimentalSubject (one per cell)
nCells = sum(projectSessionResults.numcells);
projectResults.session = cell(1, nCells);
projectResults.sessionNumber = zeros(1, nCells);
projectResults.geneticLine = cell(1, nCells);
projectResults.expSubject = cell(1, nCells);
counCell = 1;
for ii = 1:length(projectSessionResults.numcells)
    idx = counCell:counCell + projectSessionResults.numcells(ii) - 1;
    projectResults.session(idx) = {lower(projectSessionResults.sessionName{ii})};
    projectResults.sessionNumber(idx) = ii;
    projectResults.geneticLine(idx) = {lower(projectSessionResults.geneticLine{ii})};
    projectResults.expSubject(idx) = {lower(projectSessionResults.expSubject{ii})};
    counCell = counCell + projectSessionResults.numcells(ii);
end

projectResults.sessionList = unique(projectResults.session);
projectResults.geneticLineList = unique(projectResults.geneticLine);
projectResults.expSubjectList = unique(projectResults.expSubject);

projectResults.geneticLineNumber = nan(size(projectResults.sessionNumber));
for ii = 1:length(projectResults.geneticLineList)
    projectResults.geneticLineNumber(strcmpi(projectResults.geneticLine,projectResults.geneticLineList{ii})) = ii;
end

projectResults.expSubjectNumber = nan(size(projectResults.sessionNumber));
for ii = 1:length(projectResults.expSubjectList)
    projectResults.expSubjectNumber(strcmpi(projectResults.expSubject,projectResults.expSubjectList{ii})) = ii;
end

if saveMat
    disp('Saving data');
    save(fullfile(analysis_project_path, [save_as '.mat']), 'projectSessionResults', 'projectResults', '-v7.3');
end

end

%% ------------------------------------------------------------------------
function cell_metrics = loadBatch(varargin)
% loadCellMetricsBatch with its waitbar's TeX interpreter off, so session
% names like cancer2_250707_sess6 are not shown with subscripts.
% (loadCellMetricsBatch does not close a waitbar it did not create.)
h = waitbar(0, ' ', 'Name', 'Cell-metrics: loading batch');
set(findall(h, 'Type', 'text'), 'Interpreter', 'none');
closeBar = onCleanup(@() delete(h(ishandle(h))));
cell_metrics = loadCellMetricsBatch(varargin{:}, 'waitbar_handle', h);
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
