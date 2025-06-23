import { exec } from "child-process-promise";
import testConfig from "./config.test.json" with { type: "json" };
import { parse } from "path";

const {
  PATH,
  GITVERSION_EXEC_PATH,
  JQ_EXEC_PATH,
  DOTNET_ROOT
} = process.env;

const SEMVER_YEASY_PATH = parse(`${process.cwd()}/../../`).dir

beforeAll(async () => {
  await exec(`rm -rf test-workspaces || true`);
});

for (const currentTest of testConfig.tests) {
  const currentTestPath = currentTest.name
    .replace(/(: |:|\s)/, "__")
    // .replace(":", "__");
  const currentTestWorkspace = `test-workspaces/${currentTestPath}`;
  const currentTestGitRepoPath = `test-workspaces/${currentTestPath}/repo`;

  describe(currentTest.name, () => {
    beforeAll(async () => {
      await exec(`
        mkdir -p ${currentTestWorkspace}
        mkdir -p ${currentTestGitRepoPath}

        cd ${currentTestGitRepoPath}
        git config --global user.email 'example@example.com'
        git config --global user.name 'Example'
        git init
      `);

      for (const setupStep of currentTest.repoSetup) {
        await exec(setupStep, { cwd: currentTestGitRepoPath });
      }
    });

    test("change calculation", async () => {
      const changesFileName = "../output.changes.txt";
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
            GITHUB_OUTPUT: changesFileName,
            ...(DOTNET_ROOT ? { DOTNET_ROOT } : {}),
          },
          cwd: currentTestGitRepoPath,
        },
      );

      const changesCmd = await exec(`cat ${changesFileName}`, {
        cwd: currentTestGitRepoPath,
      });
      expect(changesCmd.stdout).toBe(currentTest.expectedOutputs.changes);
    });

    test("PR description calculation", async () => {
      const pullRequestDescriptionFileName = "../output.pr-description.txt";
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
            GITHUB_OUTPUT: pullRequestDescriptionFileName,
            ...(DOTNET_ROOT ? { DOTNET_ROOT } : {}),
          },
          cwd: currentTestGitRepoPath,
        },
      );

      const pullRequestDescriptionCmd = await exec(
        `cat ${pullRequestDescriptionFileName}`,
        { cwd: currentTestGitRepoPath },
      );

      expect(pullRequestDescriptionCmd.stdout).toBe(
        currentTest.expectedOutputs.pullRequestDescription,
      );
    });

    afterAll(async () => {
      await exec(`rm -r ${currentTestWorkspace} || true`);
    });
  });
}

afterAll(async () => {
  await exec(`rm -r test-workspaces || true`);
});