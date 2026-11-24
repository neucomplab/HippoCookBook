function [report, problems] = checkSessionMetadata(input)
% [report, problems] = checkSessionMetadata(input)
%   Check the metadata of a group of sessions before indexing them.
%   Read-only: it only loads files, it never writes anything.
%
% INPUT
%   input     Folder of one animal (e.g. 'Y:\cancer3'): checks every
%             subfolder with a *.session.mat. Or a cell array of session
%             folders. Or a single session folder.
%
% OUTPUTS
%   report    Table, one row per session: Project, Subject, Strain,
%             GeneticLine, Behavior, brainRegions, numCells (spikes),
%             nCellMetrics (cell_metrics).
%   problems  Cell array with the problems found (also printed).
%
% Checks
%   - session.general.name equals the folder name
%   - maze epochs exist, paradigm/environment not swapped
%   - brainRegions not empty
%   - numCells (spikes) equals number of cells in cell_metrics
%   - Project, Subject, Strain, GeneticLine and Behavior are the same in
%     all sessions (values different from the most common one are flagged)
%
% EXAMPLE
%   checkSessionMetadata('Y:\cancer3');
%
% MV 2026
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Session folders
if iscell(input)
    basepaths = input(:)';
elseif ~isempty(dir(fullfile(input, '*.session.mat')))
    basepaths = {input};
else
    sub = dir(input);
    sub = sub([sub.isdir] & ~startsWith({sub.name}, '.') & ~startsWith({sub.name}, '#'));
    basepaths = {};
    for ii = 1:length(sub)
        folder = fullfile(sub(ii).folder, sub(ii).name);
        if ~isempty(dir(fullfile(folder, '*.session.mat')))
            basepaths{end+1} = folder;
        end
    end
end
if isempty(basepaths)
    error('No sessions (*.session.mat) found in %s', char(string(input)));
end

n = length(basepaths);
problems = {};
row = struct('Session',{},'Project',{},'Subject',{},'Strain',{},'GeneticLine',{}, ...
    'Behavior',{},'brainRegions',{},'numCells',{},'nCellMetrics',{});

%% Per session
for ii = 1:n
    [~, folderName] = fileparts(basepaths{ii});
    r = struct('Session',folderName,'Project','','Subject','','Strain','','GeneticLine','', ...
        'Behavior','','brainRegions','','numCells',NaN,'nCellMetrics',NaN);

    f = dir(fullfile(basepaths{ii}, '*.session.mat'));
    try
        S = load(fullfile(f(1).folder, f(1).name), 'session');
        session = S.session;
    catch ME
        problems{end+1} = sprintf('%s: session.mat could not be loaded (%s)', folderName, ME.message);
        row(ii) = r;
        continue
    end

    % name
    if ~strcmp(session.general.name, folderName)
        problems{end+1} = sprintf('%s: session.general.name is "%s"', folderName, session.general.name);
    end

    % project / animal
    r.Project = strjoin(toList(getOr(session.general, 'projects', '')), ' ');
    r.Subject = char(getOr(session.animal, 'name', ''));
    r.Strain = char(getOr(session.animal, 'strain', ''));
    r.GeneticLine = char(getOr(session.animal, 'geneticLine', ''));
    if isempty(r.Project)
        problems{end+1} = sprintf('%s: no project', folderName);
    end

    % behavior
    behav = {};
    if isfield(session, 'epochs')
        for jj = 1:length(session.epochs)
            ep = session.epochs{jj};
            paradigm = char(getOr(ep, 'behavioralParadigm', ''));
            environment = char(getOr(ep, 'environment', ''));
            if contains(paradigm, 'Maze')
                behav{end+1} = lower(environment);
                if strcmpi(environment, 'Maze') && startsWith(lower(paradigm), 'maze')
                    problems{end+1} = sprintf('%s: epoch %d environment is just "Maze"', folderName, jj);
                elseif ~startsWith(lower(paradigm), 'maze') % 'Maze', 'Maze1'... are fine; 'TMaze' is not
                    problems{end+1} = sprintf('%s: epoch %d paradigm "%s" / environment "%s" (swapped?)', ...
                        folderName, jj, paradigm, environment);
                end
            elseif contains(lower(environment), 'maze')
                problems{end+1} = sprintf('%s: epoch %d environment "%s" but paradigm "%s" (swapped?)', ...
                    folderName, jj, environment, paradigm);
            end
        end
    end
    r.Behavior = strjoin(unique(behav, 'stable'), ' ');

    % brain regions
    if isfield(session, 'brainRegions') && isstruct(session.brainRegions) && ~isempty(fieldnames(session.brainRegions))
        r.brainRegions = strjoin(fieldnames(session.brainRegions)', ' ');
    else
        problems{end+1} = sprintf('%s: no brainRegions', folderName);
    end

    % number of cells: spikes vs cell_metrics
    fs = dir(fullfile(basepaths{ii}, '*.spikes.cellinfo.mat'));
    if isempty(fs)
        problems{end+1} = sprintf('%s: no spikes.cellinfo.mat', folderName);
    else
        S = load(fullfile(fs(1).folder, fs(1).name), 'spikes');
        r.numCells = S.spikes.numcells;
    end
    fc = dir(fullfile(basepaths{ii}, '*.cell_metrics.cellinfo.mat'));
    if isempty(fc)
        problems{end+1} = sprintf('%s: no cell_metrics.cellinfo.mat', folderName);
    else
        S = load(fullfile(fc(1).folder, fc(1).name), 'cell_metrics');
        r.nCellMetrics = numel(S.cell_metrics.UID);
    end
    if ~isnan(r.numCells) && ~isnan(r.nCellMetrics) && r.numCells ~= r.nCellMetrics
        problems{end+1} = sprintf('%s: %d cells in spikes but %d in cell_metrics', folderName, r.numCells, r.nCellMetrics);
    end

    row(ii) = r;
end

report = struct2table(row(:), 'AsArray', true);

%% Consistency across sessions
if n > 1
    for fld = {'Project','Subject','Strain','GeneticLine','Behavior'}
        values = report.(fld{1});
        [u, ~, idx] = unique(values);
        if numel(u) > 1
            counts = accumarray(idx, 1);
            [~, common] = max(counts);
            odd = find(idx ~= common);
            for jj = odd(:)'
                problems{end+1} = sprintf('%s: %s is "%s" (most sessions: "%s")', ...
                    report.Session{jj}, fld{1}, values{jj}, u{common});
            end
        end
    end
end

%% Print
disp(report);
if isempty(problems)
    fprintf('No problems found in %d sessions.\n', n);
else
    fprintf('%d problem(s) found:\n', numel(problems));
    fprintf('  - %s\n', problems{:});
end

end

%% ------------------------------------------------------------------------
function v = getOr(s, field, default)
if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
    v = s.(field);
else
    v = default;
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
