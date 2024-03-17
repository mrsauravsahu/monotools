import { test as it } from "uvu";
import * as assert from "uvu/assert";
import { exec } from "child-process-promise";
import testConfig from "./config.test.json" assert { type: "json" };

const { ROOT_TEST_FOLDER, SEMVER_YEASY_ROOT_DIRECTORY, GITVERSION_EXEC_PATH    ,       JQ_EXEC_PATH,} =
  process.env;
await exec(`rm -rf ${ROOT_TEST_FOLDER}/test-workspaces || true`);

for (const currentTest of testConfig.tests) {
  const currentTestPath = currentTest.name.replace(": ", "__");
  const currentTestWorkspace = `test-workspaces/${currentTestPath}`;
  const currentTestGitRepoPath = `test-workspaces/${currentTestPath}/repo`;

  it.before(async () => {
    await exec(`
    mkdir -p ${ROOT_TEST_FOLDER}/${currentTestWorkspace}
    mkdir -p ${ROOT_TEST_FOLDER}/${currentTestGitRepoPath}

    cd ${currentTestGitRepoPath}
    git config --global user.email 'example@example.com'
    git config --global user.name 'Example'
    git init
    `);

    for (const setupStep of currentTest.repoSetup) {
      await exec(setupStep, { cwd: currentTestGitRepoPath });
    }
  });

  it(`${currentTest.name}: change calculation`, async () => {
    // Test: Version calculation
    const changesFileName = "../output.changes.txt";
    
    await exec(
      `bash ${SEMVER_YEASY_ROOT_DIRECTORY}/semver-yeasy.sh changed ${currentTest.inputs.env.GITVERSION_REPO_TYPE}`,
      {
        env: {
          ...currentTest.inputs.env,
          ENV: 'LOCAL',
          JQ_EXEC_PATH,
          GITVERSION_EXEC_PATH,
          GITHUB_OUTPUT: changesFileName,
        },
        cwd: currentTestGitRepoPath,
      },
    );

    const changesCmd = await exec(`cat ${changesFileName}`, {
      cwd: currentTestGitRepoPath,
    });
    assert.equal(changesCmd.stdout, currentTest.expectedOutputs.changes);
  });

  it(`${currentTest.name}: PR description calculation`, async () => {
    // Test: PR description calculation
    const pullRequestDescriptionFileName = "../output.pr-description.txt";
    await exec(
      `bash ${SEMVER_YEASY_ROOT_DIRECTORY}/semver-yeasy.sh calculate-version ${currentTest.inputs.env.GITVERSION_REPO_TYPE}`,
      {
        env: {
          ...currentTest.inputs.env,
          ENV: 'LOCAL',
          JQ_EXEC_PATH,
          GITVERSION_EXEC_PATH,
          GITHUB_OUTPUT: pullRequestDescriptionFileName,
        },
        cwd: currentTestGitRepoPath,
      },
    );

    const pullRequestDescriptionCmd = await exec(
      `cat ${pullRequestDescriptionFileName}`,
      { cwd: currentTestGitRepoPath },
    );
    assert.equal(
      pullRequestDescriptionCmd.stdout,
      currentTest.expectedOutputs.pullRequestDescription,
    );
  });

  // it.after(async () => await exec(`rm -r ${currentTestWorkspace}`));
}

it.run();
