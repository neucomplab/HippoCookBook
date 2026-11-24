%% BatchScript_analysis_example
% Template to run an analysis on every indexed session of a project.
% Copy this script, set targetProject and put your code in the loop.

clear; close all
targetProject = 'Crabcer'; % project name, or 'all'

sessionsTable = getIndexedSessions();
if ~strcmpi(targetProject, 'all')
    inProject = cellfun(@(x) any(strcmpi(x, targetProject)), sessionsTable.Project);
    sessionsTable = sessionsTable(inProject, :);
end

for ii = 1:height(sessionsTable)
    fprintf(' > %3.i/%3.i %s \n', ii, height(sessionsTable), sessionsTable.SessionName{ii});
    cd(sessionsTable.basepath{ii});
    try

        %%% your code goes here...
        getAverageCCG('force',true);
        %%%

        close all;
    catch ME
        warning('%s: analysis was not possible (%s)', sessionsTable.SessionName{ii}, ME.message);
    end
end
