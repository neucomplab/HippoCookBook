function stacked = stackSessionResult(toStack,numCells,varargin)
% stacked = stackSessionResult(toStack,numCells,varargin)
%   Stack all fields of a cell array of structures (one per session) along
%   the cells dimension.
%
% INPUTS
%   toStack         Cell array, one structure per session. Sessions without
%                   data (NaN, empty or not a struct) are filled with NaN.
%   numCells        Number of cells per session (one value per session).
%   exampleSession  Session used as template for the fields (default: first
%                   session with data).
%
% Fields with a dimension equal to numCells in ALL sessions are stacked
% along that dimension. Numeric vectors without cells dimension are
% repeated for each cell. Nested structures are flattened up to 3 levels
% (struct.a.b -> stacked.a_b) for fields with a cells dimension.
%
% MV 2022, 2026 (bug fixes: one session, failure cascade, first session
% missing, numCells mismatch, level-3 flattening, non-double types, cells)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

p = inputParser;
addRequired(p,'toStack',@iscell);
addRequired(p,'numCells',@isnumeric);
addParameter(p,'exampleSession',[],@isnumeric);
addParameter(p,'activateTry',true,@islogical); % kept for compatibility

parse(p, toStack,numCells,varargin{:});

exampleSession = p.Results.exampleSession;

if isempty(toStack)
    error('Input data is empty');
end
if isempty(numCells)
    error('Number of cells field not provided');
end
numCells = numCells(:);
if numel(numCells) ~= numel(toStack)
    error('numCells has %i values but there are %i sessions', numel(numCells), numel(toStack));
end

% sessions without data -> NaN
for mm = 1:length(toStack)
    if isempty(toStack{mm}) || ~isstruct(toStack{mm})
        toStack{mm} = NaN;
    end
end
hasData = cellfun(@isstruct, toStack);
if ~any(hasData)
    error('No session has data to stack');
end
if isempty(exampleSession) || exampleSession > numel(toStack) || ~hasData(exampleSession)
    exampleSession = find(hasData, 1);
end
ex = toStack{exampleSession};
nEx = numCells(exampleSession);
missing = find(~hasData);
clonned = ~isempty(missing);

%% clone missing sessions from the example session, filled with NaN
names = fieldnames(ex);
toStack_clon = cell(size(toStack));
for mm = missing(:)'
    toStack_clon{mm} = struct();
    for ii = 1:length(names)
        toStack_clon{mm}.(names{ii}) = nanLike(ex.(names{ii}), nEx, numCells(mm));
    end
end

%% flatten nested structures (up to 3 levels) for fields with cells dimension
for ii = 1:length(names)
    if ~isstruct(ex.(names{ii}))
        continue
    end
    l2_names = fieldnames(ex.(names{ii}));
    for jj = 1:length(l2_names)
        v2 = ex.(names{ii}).(l2_names{jj});
        if isNumericLike(v2) && any(size(v2) == nEx)
            fprintf('Flattening %s... \n', l2_names{jj});
            toStack = flattenField(toStack, {names{ii}, l2_names{jj}}, v2);
        elseif isstruct(v2)
            l3_names = fieldnames(v2);
            for kk = 1:length(l3_names)
                v3 = v2.(l3_names{kk});
                if isNumericLike(v3) && any(size(v3) == nEx)
                    fprintf('Flattening %s... \n', l3_names{kk});
                    toStack = flattenField(toStack, {names{ii}, l2_names{jj}, l3_names{kk}}, v3);
                end
            end
        elseif strcmpi('timestamps', l2_names{jj})
            flatName = [names{ii} '_' l2_names{jj}];
            for mm = find(hasData(:))'
                if hasNested(toStack{mm}, {names{ii}, l2_names{jj}})
                    toStack{mm}.(flatName) = toStack{mm}.(names{ii}).(l2_names{jj});
                else
                    toStack{mm}.(flatName) = v2;
                end
            end
            for mm = missing(:)'
                toStack_clon{mm}.(flatName) = v2;
            end
        end
    end
end

    function toStack = flattenField(toStack, path, exampleValue)
        % copy struct.(a).(b)... to struct.a_b for every session
        flatName = strjoin(path, '_');
        for mm2 = 1:length(toStack)
            if hasData(mm2) && hasNested(toStack{mm2}, path)
                toStack{mm2}.(flatName) = getfield(toStack{mm2}, path{:});
            elseif hasData(mm2) % field missing in this session
                toStack{mm2}.(flatName) = nanLike(exampleValue, nEx, numCells(mm2));
            else
                toStack_clon{mm2}.(flatName) = nanLike(exampleValue, nEx, numCells(mm2));
            end
        end
    end

for mm = missing(:)'
    toStack{mm} = toStack_clon{mm};
end

%% stack
names = fieldnames(toStack{exampleSession});
nSessions = length(toStack);
stacked = struct();
for ii = 1:length(names)
    name = names{ii};
    try
        % fields missing in some session -> NaN
        for mm = 1:nSessions
            if ~isfield(toStack{mm}, name)
                toStack{mm}.(name) = nanLike(toStack{exampleSession}.(name), nEx, numCells(mm));
            end
        end

        ndims_field = cellfun(@(s) ndims(s.(name)), toStack);
        if length(unique(ndims_field)) > 1
            error('More than one dimension setting of data per field!')
        end
        size_field = zeros(nSessions, ndims_field(1));
        type_field = cell(nSessions, 1);
        for jj = 1:nSessions
            size_field(jj,:) = size(toStack{jj}.(name));
            type_field{jj} = typeOf(toStack{jj}.(name));
        end
        dims = max(size_field, [], 1);
        type_field = unique(type_field);

        matches = size_field == numCells;   % sessions x dims
        dim_cells_data = all(matches, 1);

        % a cells dimension in most sessions but not all: numCells does not
        % match the result in some sessions (e.g. result computed before
        % re-sorting). Do not stack instead of producing wrong data.
        if nSessions > 1 && ~any(dim_cells_data)
            partial = find(sum(matches, 1) > nSessions/2, 1);
            if ~isempty(partial)
                warning('Field %s not stacked: number of cells does not match numCells in session(s) %s', ...
                    name, mat2str(find(~matches(:,partial))'));
                continue
            end
        end

        if length(type_field) > 1
            if any(strcmpi(type_field,'struct')) && clonned % unless a structure was clonned
                type_field = 'struct';
            elseif any(strcmpi(type_field,'cell')) && clonned
                type_field = 'struct';
            else
                type_field = 'multiple';
                warning('Field %s: more than one type of data!', name)
            end
        else
            type_field = type_field{1};
        end

        dim_sorted = 1:ndims_field(1);
        dim_sorted = [dim_sorted(dim_cells_data) dim_sorted(~dim_cells_data)];
        dims = dims(dim_sorted);

        if any(dim_cells_data) && strcmpi(type_field,'double')
            % stack by the cells in first dimension
            stacked.(name) = [];
            otherDims = repmat({':'}, 1, length(dims)-1);
            for jj = 1:nSessions
                values = permute(double(toStack{jj}.(name)), dim_sorted);
                temp = nan(dims);
                idx = arrayfun(@(d) 1:size(values,d), 1:length(dims), 'UniformOutput', false);
                temp(idx{:}) = values;
                temp = temp(1:numCells(jj), otherDims{:});
                stacked.(name) = cat(1, stacked.(name), temp);
            end
        elseif any(dim_cells_data) && strcmpi(type_field,'cell') && any(dims==1) && length(dims)<3
            stacked.(name) = [];
            for jj = 1:nSessions
                values = permute(toStack{jj}.(name), dim_sorted);
                stacked.(name) = cat(1, stacked.(name), values);
            end
        elseif contains(name, 'timestamps')
            stacked.(name) = toStack{exampleSession}.(name);
        elseif strcmpi(type_field,'double') && any(dims==1) && length(dims)<3
            % vector without cells dimension: repeat for each cell
            stacked.(name) = [];
            for jj = 1:nSessions
                values = double(toStack{jj}.(name));
                values = repmat(values(:)', numCells(jj), 1);
                temp = nan(numCells(jj), max(dims));
                temp(1:size(values,1), 1:size(values,2)) = values;
                stacked.(name) = cat(1, stacked.(name), temp);
            end
        else
            fprintf('Field %s can not be stacked \n', name);
        end
    catch ME
        warning('Field %s failed to be stacked: %s', name, ME.message);
    end
end

stacked.sessionNumber = [];
for jj = 1:length(numCells)
    stacked.sessionNumber = cat(1,stacked.sessionNumber,jj*ones(numCells(jj),1));
end

end

%% ------------------------------------------------------------------------
function out = nanLike(example, nEx, nNew)
% same shape as example with the cells dimension resized to nNew, filled
% with NaN (numeric/logical) or empty cells (cell). Char is copied.
if isnumeric(example) || islogical(example) || iscell(example)
    sz = size(example);
    sz(sz == nEx) = nNew;
    if iscell(example)
        out = cell(sz);
    else
        out = nan(sz);
    end
elseif ischar(example)
    out = example;
else
    out = NaN;
end
end

function t = typeOf(x)
% numeric and logical types are stacked as double
if isnumeric(x) || islogical(x)
    t = 'double';
else
    t = class(x);
end
end

function tf = isNumericLike(x)
tf = isnumeric(x) || islogical(x);
end

function tf = hasNested(s, path)
% true if s.(path{1}).(path{2})... exists
tf = true;
for ii = 1:length(path)
    if ~isstruct(s) || ~isfield(s, path{ii})
        tf = false;
        return
    end
    s = s.(path{ii});
end
end
