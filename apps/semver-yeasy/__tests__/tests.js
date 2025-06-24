import { exec } from "child-process-promise";
import testConfig from "./config.test.json" with { type: "json" };
import * as path from "path";

const {
  PATH,
  GITVERSION_EXEC_PATH,
  JQ_EXEC_PATH,
  DOTNET_ROOT
} = process.env;

const SEMVER_YEASY_PATH = path.resolve(`${process.cwd()}/../`)
const MONOTOOLS_PATH = path.resolve(`${process.cwd()}/../../../`)

beforeAll(async () => {
  await exec(`rm -rf test-workspaces || true`);
});

for (const currentTest of testConfig.tests) {
  const currentTestPath = currentTest.name
    .replace(/(: |:|\s)/g, "__")

  const currentTestWorkspace = path.resolve(`${SEMVER_YEASY_PATH}/__tests__/test-workspaces/${currentTestPath}`);
  const currentTestGitRepoPath = path.resolve(`${SEMVER_YEASY_PATH}/__tests__/test-workspaces/${currentTestPath}/repo`);

  describe(currentTest.name, () => {
    beforeEach(async () => {
      await exec(`
rm -rf ${currentTestWorkspace} > /dev/null 2>&1 || true
mkdir -p ${currentTestGitRepoPath}
`);

      await exec(`
git init
git config user.email 'example@example.com'
git config user.name 'Example'
`, { cwd: currentTestGitRepoPath });

      for (const setupStep of currentTest.repoSetup) {
        await exec(setupStep, { env: { MONOTOOLS_PATH }, cwd: currentTestGitRepoPath });
      }
    });

    test("change calculation", async () => {
      const changesFileName = path.resolve(`${currentTestWorkspace}/output.changes.txt`);
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
            MONOTOOLS_PATH,
            GITHUB_OUTPUT: changesFileName,
            ...(DOTNET_ROOT ? { DOTNET_ROOT } : {}),
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
      const pullRequestDescriptionFileName = path.resolve(`${currentTestWorkspace}/output.pr-description.txt`);
      const cmd = `bash ${SEMVER_YEASY_PATH}/semver-yeasy.sh calculate-version ${currentTest.inputs.env.GITVERSION_REPO_TYPE}`;
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
            MONOTOOLS_PATH,
            GITHUB_OUTPUT: pullRequestDescriptionFileName,
            ...(DOTNET_ROOT ? { DOTNET_ROOT } : {}),
          },
          cwd: currentTestGitRepoPath,
          shell: "/bin/bash"
        },
      );

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
  await exec(`rm -r test-workspaces || true`);
});