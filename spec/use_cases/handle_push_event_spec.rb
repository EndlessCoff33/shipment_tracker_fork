require 'rails_helper'
require 'handle_push_event'

RSpec.describe HandlePushEvent do
  let(:loader) { double }
  let(:repository) { double }

  before do
    allow_any_instance_of(CommitStatus).to receive(:reset)
    allow(GitRepositoryLocation).to receive(:repo_tracked?).and_return(true)
    allow(GitRepositoryLoader).to receive(:from_rails_config).and_return(loader)
    allow(loader).to receive(:load).and_return(repository)
    allow(repository).to receive(:commit_on_master?).and_return(false)
  end

  describe 'validation' do
    it 'fails if repo not audited' do
      allow(GitRepositoryLocation).to receive(:repo_tracked?).and_return(false)

      payload = instance_double(
        Payloads::Github,
        full_repo_name: 'owner/repo',
        after_sha: 'abc1234',
      )

      result = HandlePushEvent.run(payload)

      expect(result).to fail_with(:repo_not_under_audit)
    end

    it 'fails if after commit SHA is "0000000"' do
      payload = instance_double(
        Payloads::Github,
        full_repo_name: 'owner/repo',
        before_sha: 'abc1234',
        after_sha: '000000000000000000000000000000000000000000',
      )

      result = HandlePushEvent.run(payload)
      expect(result).to fail_with(:invalid_sha)
    end
  end

  describe 'updating remote head' do
    it 'updates the corresponding repository location' do
      allow_any_instance_of(CommitStatus).to receive(:not_found)

      github_payload = instance_double(
        Payloads::Github,
        full_repo_name: 'owner/repo',
        before_sha: 'abc1234',
        after_sha: 'def4567',
        push_to_master?: false,
      )

      git_repository_location = instance_double(GitRepositoryLocation)
      allow(GitRepositoryLocation).to receive(:find_by_full_repo_name).and_return(git_repository_location)

      expect(git_repository_location).to receive(:update).with(remote_head: 'def4567')
      HandlePushEvent.run(github_payload)
    end

    it 'fails when repo not found' do
      github_payload = instance_double(Payloads::Github, full_repo_name: 'owner/repo', after_sha: 'abc1234')

      allow(GitRepositoryLocation).to receive(:find_by_full_repo_name).and_return(nil)

      result = HandlePushEvent.run(github_payload)
      expect(result).to fail_with(:repo_not_found)
    end
  end

  describe 'resetting commit status' do
    before do
      git_repository_location = instance_double(GitRepositoryLocation)
      allow(GitRepositoryLocation).to receive(:find_by_full_repo_name).and_return(git_repository_location)
      allow(git_repository_location).to receive(:update)
    end

    it 'resets the GitHub commit status' do
      allow_any_instance_of(CommitStatus).to receive(:not_found)

      github_payload = instance_double(
        Payloads::Github,
        full_repo_name: 'owner/repo',
        before_sha: 'abc1234',
        after_sha: 'def4567',
        push_to_master?: false,
      )

      expect_any_instance_of(CommitStatus).to receive(:reset).with(
        full_repo_name: github_payload.full_repo_name,
        sha: github_payload.after_sha,
      )

      HandlePushEvent.run(github_payload)
    end

    context 'commit is pushed to master' do
      it 'fails with :protected_branch' do
        payload = instance_double(
          Payloads::Github,
          full_repo_name: 'owner/repo',
          before_sha: 'def123',
          after_sha: 'abc1234',
          push_to_master?: true,
        )
        expect_any_instance_of(CommitStatus).not_to receive(:reset)

        result = HandlePushEvent.run(payload)
        expect(result).to fail_with(:protected_branch)
      end
    end
  end

  describe 'relinking tickets' do
    before do
      git_repository_location = instance_double(GitRepositoryLocation, update: nil)
      allow(GitRepositoryLocation).to receive(:find_by_full_repo_name).and_return(git_repository_location)
      allow(Repositories::TicketRepository).to receive(:new).and_return(ticket_repo)
    end

    let(:ticket_repo) { instance_double(Repositories::TicketRepository, tickets_for_versions: tickets) }
    let(:tickets) { [] }

    context 'when branching off master' do
      before do
        allow(GitRepositoryLoader).to receive(:from_rails_config).and_return(loader)
        allow(loader).to receive(:load).with('app1').and_return(repository)
        allow(repository).to receive(:commit_on_master?).with('abc1234').and_return(true)
        allow_any_instance_of(CommitStatus).to receive(:not_found)
      end

      it 'does not re-link' do
        expect(JiraClient).not_to receive(:post_comment)

        github_payload = instance_double(
          Payloads::Github,
          full_repo_name: 'owner/app1',
          before_sha: 'abc1234',
          after_sha: 'def4567',
          push_to_master?: false,
        )

        HandlePushEvent.run(github_payload)
      end

      it 'posts not found status' do
        expect_any_instance_of(CommitStatus).to receive(:not_found).with(
          full_repo_name: 'owner/app1',
          sha: 'def4567',
        )

        github_payload = instance_double(
          Payloads::Github,
          full_repo_name: 'owner/app1',
          before_sha: 'abc1234',
          after_sha: 'def4567',
          push_to_master?: false,
        )

        HandlePushEvent.run(github_payload)
      end
    end

    context 'when there are no previously linked tickets' do
      let(:tickets) { [] }

      it 'does not post a JIRA comment' do
        allow_any_instance_of(CommitStatus).to receive(:not_found)

        expect(JiraClient).not_to receive(:post_comment)

        github_payload = instance_double(
          Payloads::Github,
          full_repo_name: 'owner/repo',
          before_sha: 'abc1234',
          after_sha: 'def4567',
          push_to_master?: false,
        )

        HandlePushEvent.run(github_payload)
      end

      it 'posts a "failure" commit status to GitHub' do
        expect_any_instance_of(CommitStatus).to receive(:not_found).with(
          full_repo_name: 'owner/repo',
          sha: 'def4567',
        )

        github_payload = instance_double(
          Payloads::Github,
          full_repo_name: 'owner/repo',
          before_sha: 'abc1234',
          after_sha: 'def4567',
          push_to_master?: false,
        )

        HandlePushEvent.run(github_payload)
      end
    end

    context 'when there are previously linked tickets' do
      let(:tickets) {
        [
          instance_double(Ticket, key: 'ISSUE-1', paths: paths_issue1),
          instance_double(Ticket, key: 'ISSUE-2', paths: paths_issue2),
        ]
      }

      context 'with multiple Feature Reviews' do
        context 'with one app per Feature Review' do
          let(:paths_issue1) {
            [
              feature_review_path(app1: 'abc5678'),
              feature_review_path(app1: 'def1234'),
            ]
          }

          let(:paths_issue2) {
            [
              feature_review_path(app1: 'bcd1234'),
              feature_review_path(app1: 'ced1234'),
            ]
          }

          it 'posts linking comment to JIRA with relevant Feature Review' do
            expect(JiraClient).to receive(:post_comment).once.with(
              tickets.first.key,
              "[Feature ready for review|#{feature_review_url(app1: 'abc1234')}]",
            )

            github_payload = instance_double(
              Payloads::Github,
              full_repo_name: 'owner/app1',
              before_sha: 'def1234',
              after_sha: 'abc1234',
              push_to_master?: false,
            )
            HandlePushEvent.run(github_payload)
          end
        end

        context 'with multiple apps per Feature Review' do
          let(:paths_issue1) {
            [
              feature_review_path(app1: 'bcd1234', app2: 'def1234'),
              feature_review_path(app3: 'abc1234', app4: 'ced1234'),
            ]
          }

          let(:paths_issue2) {
            [
              feature_review_path(app2: 'def1234', app5: 'fdc1234'),
            ]
          }

          it 'posts linking comment to JIRA with relevant Feature Review' do
            expect(JiraClient).to receive(:post_comment).once.ordered.with(
              tickets.first.key,
              "[Feature ready for review|#{feature_review_url(app1: 'bcd1234', app2: 'ffd1234')}]",
            )
            expect(JiraClient).to receive(:post_comment).once.ordered.with(
              tickets.second.key,
              "[Feature ready for review|#{feature_review_url(app2: 'ffd1234', app5: 'fdc1234')}]",
            )

            github_payload = instance_double(
              Payloads::Github,
              full_repo_name: 'owner/app2',
              before_sha: 'def1234',
              after_sha: 'ffd1234',
              push_to_master?: false,
            )
            HandlePushEvent.run(github_payload)
          end
        end
      end
    end

    context 'when the linking fails for a ticket' do
      let(:tickets) {
        [
          instance_double(Ticket, key: 'ISSUE-1', paths: paths_issue1),
          instance_double(Ticket, key: 'ISSUE-2', paths: paths_issue2),
        ]
      }

      let(:paths_issue1) {
        [
          feature_review_path(app1: 'abc1234'),
          feature_review_path(app1: 'def1234'),
        ]
      }

      let(:paths_issue2) {
        [
          feature_review_path(app1: 'abc1234'),
          feature_review_path(app1: 'caa1234'),
        ]
      }

      it 'rescues and continues to link other tickets' do
        allow_any_instance_of(CommitStatus).to receive(:error)
        allow(JiraClient).to receive(:post_comment).with(tickets.first.key, anything)
          .and_raise(JiraClient::InvalidKeyError)

        github_payload = instance_double(
          Payloads::Github,
          full_repo_name: 'owner/app1',
          before_sha: 'abc1234',
          after_sha: 'faa1234',
          push_to_master?: false,
        )

        expect(JiraClient).to receive(:post_comment).with(tickets.second.key, anything)

        HandlePushEvent.run(github_payload)
      end

      it 'posts "error" status to GitHub on InvalidKeyError' do
        allow(JiraClient).to receive(:post_comment).and_raise(JiraClient::InvalidKeyError)

        github_payload = instance_double(
          Payloads::Github,
          full_repo_name: 'owner/app1',
          before_sha: 'abc1234',
          after_sha: 'faa1234',
          push_to_master?: false,
        )

        expect_any_instance_of(CommitStatus).to receive(:error).once.with(
          full_repo_name: 'owner/app1',
          sha: 'faa1234',
        )

        HandlePushEvent.run(github_payload)
      end

      it 'posts "error" status to GitHub on any other error' do
        allow(JiraClient).to receive(:post_comment).and_raise

        github_payload = instance_double(
          Payloads::Github,
          full_repo_name: 'owner/app1',
          before_sha: 'abc1234',
          after_sha: 'faa1234',
          push_to_master?: false,
        )

        expect_any_instance_of(CommitStatus).to receive(:error).once.with(
          full_repo_name: 'owner/app1',
          sha: 'faa1234',
        )

        HandlePushEvent.run(github_payload)
      end
    end
  end
end
