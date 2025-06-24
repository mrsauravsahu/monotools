import { exec } from "child-process-promise";
import testConfig from "./config.test.json" with { type: "json" };
import * as path from "path";
import * as fs from 'fs';

const {
  PATH,
  GITVERSION_EXEC_PATH,
  JQ_EXEC_PATH,
  DOTNET_ROOT
} = process.env;

const SEMVER_YEASY_PATH = path.resolve(`${process.cwd()}/../`)

beforeAll(async () => {
  await exec(`rm -rf test-workspaces || true`);
});

for (const currentTest of testConfig.tests) {
  const currentTestPath = currentTest.name
    .replace(/(: |:|\s)/g, "__")

  const currentTestWorkspace = path.resolve(`${SEMVER_YEASY_PATH}/__tests__/test-workspaces/${currentTestPath}`);
  const currentTestWorkspaceChangeCalculation = path.resolve(`${currentTestWorkspace}-change-calculation`);
  const currentTestWorkspacePRDescriptionCalculation = path.resolve(`${currentTestWorkspace}-pr-description-calculation`);

  describe(currentTest.name, () => {
    beforeAll(async () => {
      await exec(`
mkdir -p ${currentTestWorkspaceChangeCalculation}/repo
mkdir -p ${currentTestWorkspacePRDescriptionCalculation}/repo
`);

      const gitRepoSetup = `
git init
git config user.email 'example@example.com'
git config user.name 'Example'
`

      for (const setupStep of [gitRepoSetup, ...currentTest.repoSetup]) {
        await exec(setupStep, { env: { SEMVER_YEASY_PATH }, cwd: `${currentTestWorkspaceChangeCalculation}/repo` });
        await exec(setupStep, { env: { SEMVER_YEASY_PATH }, cwd: `${currentTestWorkspacePRDescriptionCalculation}/repo` });
      }
    });

    test("change calculation", async () => {
      const currentCasePath = `${currentTestWorkspace}-change-calculation`;
      const currentTestGitRepoPath = `${currentCasePath}/repo`;
      const changesFileName = path.resolve(`${currentCasePath}/output.changes.txt`);
      const cmd = `bash ${SEMVER_YEASY_PATH}/semver-yeasy.sh changed ${currentTest.inputs.env.GITVERSION_REPO_TYPE}`;
      // console.log(`Running command: ${cmd}`);
      await exec(
        cmd,
        {
          env: {
            ...currentTest.inputs.env,
            PATH,
            JQ_EXEC_PATH,
            GITVERSION_EXEC_PATH,
            SEMVER_YEASY_PATH,
            GITHUB_OUTPUT: changesFileName,
            // ...(DOTNET_ROOT ? { DOTNET_ROOT } : {}),
            // ...(DOTNET_ROOT ? { PATH: `${DOTNET_ROOT}:${PATH}` } : {}),
          },
          cwd: currentTestGitRepoPath,
          shell: "/bin/bash"
        },
      );

      const changesCmd = await exec(`cat ${changesFileName}`, {
        cwd: currentTestGitRepoPath,
      });

      expect(changesCmd.stdout).toBe(currentTest.expectedOutputs.changes);
    });

    test("PR description calculation", async () => {
      const currentCasePath = `${currentTestWorkspace}-pr-description-calculation`;
      const currentTestGitRepoPath = `${currentCasePath}/repo`;
      const pullRequestDescriptionFileName = path.resolve(`${currentCasePath}/output.pr-description.txt`);
      const cmd = `bash ${SEMVER_YEASY_PATH}/semver-yeasy.sh calculate-version ${currentTest.inputs.env.GITVERSION_REPO_TYPE}`;
      // console.log(`Running command: ${cmd}`);
      const pullRequestDescriptionCalculationCmdExec = await exec(
        cmd,
        {
          env: {
            ...currentTest.inputs.env,
            PATH,
            JQ_EXEC_PATH,
            GITVERSION_EXEC_PATH,
            SEMVER_YEASY_PATH,
            GITHUB_OUTPUT: pullRequestDescriptionFileName,
            // ...(DOTNET_ROOT ? { DOTNET_ROOT } : {}),
            // ...(DOTNET_ROOT ? { PATH: `${DOTNET_ROOT}:${PATH}` } : {}),
          },
          cwd: currentTestGitRepoPath,
          shell: "/bin/bash"
        },
      );

      const pullRequestDescriptionCalculationLogs = path.resolve(`${currentCasePath}/output.pr-description.log`);
      fs.writeFileSync(pullRequestDescriptionCalculationLogs, pullRequestDescriptionCalculationCmdExec.stdout + "\n" + "---ERROR_LOGS---" + "\n" +
        pullRequestDescriptionCalculationCmdExec.stderr
      )

      const pullRequestDescriptionCmd = await exec(
        `cat ${pullRequestDescriptionFileName}`,
        { cwd: currentTestGitRepoPath, shell: "/bin/bash" },

      );

      expect(pullRequestDescriptionCmd.stdout).toBe(
        currentTest.expectedOutputs.pullRequestDescription,
      );
    });
  });
}

afterAll(async () => {
  // await exec(`rm -r test-workspaces || true`);
});