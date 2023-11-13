import { test as it } from 'uvu';
import * as assert from 'uvu/assert';
import { exec } from 'child-process-promise';
import testConfig from './config.test.json' assert { type: "json" };

var { ROOT_TEST_FOLDER, SEMVER_YEASY_ROOT_DIRECTORY, GITVERSION_EXEC_PATH } = process.env;
await exec(`rm -rf ${ROOT_TEST_FOLDER}/test-workspaces || true`)

testConfig.tests.forEach(currentTest => {
  const currentTestPath = currentTest.name.replace(': ', '__')
  const currentTestWorkspace = `test-workspaces/${currentTestPath}`
  const currentTestGitRepoPath = `test-workspaces/${currentTestPath}/repo`

  it.before(async () => {
    await exec(`
    mkdir -p ${ROOT_TEST_FOLDER}/${currentTestWorkspace}
    mkdir -p ${ROOT_TEST_FOLDER}/${currentTestGitRepoPath}

    cd ${currentTestGitRepoPath}
    git config --global user.email 'example@example.com'
    git config --global user.name 'Example'
    git init
    `)

    for (var setupStep of currentTest.repoSetup) {
      await exec(setupStep, { cwd: currentTestGitRepoPath });
    }
  })

  it(`${currentTest.name}`, async () => {
    const changesFileName = `../output.changes.txt`

    await exec(
      `GITHUB_OUTPUT=\'${changesFileName}\' bash ${SEMVER_YEASY_ROOT_DIRECTORY}/semver-yeasy.sh changed ${currentTest.inputs.env.GITVERSION_REPO_TYPE}`, {
      env: currentTest.inputs.env,
      cwd: currentTestGitRepoPath
    })

    const changesCmd = await exec(`cat ${changesFileName}`, { cwd: currentTestGitRepoPath })
    assert.equal(changesCmd.stdout, currentTest.expectedOutputs.changes)

    // --------

    const pullRequestDescriptionFileName = `../output.pr-description.txt`
    var calculationCommand = await exec(
      `GITHUB_OUTPUT=\'${pullRequestDescriptionFileName}\' bash ${SEMVER_YEASY_ROOT_DIRECTORY}/semver-yeasy.sh calculate-version ${currentTest.inputs.env.GITVERSION_REPO_TYPE}`, {
      env: {
        ...currentTest.inputs.env,
        GITVERSION_EXEC_PATH
      },
      cwd: currentTestGitRepoPath
    })

    console.log(calculationCommand.stdout)

    const pullRequestDescriptionCmd = await exec(`cat ${pullRequestDescriptionFileName}`, { cwd: currentTestGitRepoPath })
    assert.equal(pullRequestDescriptionCmd.stdout, currentTest.expectedOutputs.pullRequestDescription,
    )

  })

  it.after(async () => await exec(`rm -r ${currentTestWorkspace}`))
})

it.run();
