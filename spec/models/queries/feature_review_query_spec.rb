# frozen_string_literal: true
require 'rails_helper'
require 'queries/feature_review_query'

RSpec.describe Queries::FeatureReviewQuery do
  let(:build_repository) { instance_double(Repositories::BuildRepository) }
  let(:deploy_repository) { instance_double(Repositories::DeployRepository) }
  let(:manual_test_repository) { instance_double(Repositories::ManualTestRepository) }
  let(:ticket_repository) { instance_double(Repositories::TicketRepository) }
  let(:uatest_repository) { instance_double(Repositories::UatestRepository) }
  let(:release_exception_repository) { instance_double(Repositories::ReleaseExceptionRepository) }

  let(:expected_builds) { double('expected builds') }
  let(:expected_deploys) { double('expected deploys') }
  let(:expected_qa_submission) { double('expected qa submission') }
  let(:expected_tickets) { double('expected tickets') }
  let(:expected_uatest) { double('uatest') }
  let(:expected_release_exception) { double('release_exception') }

  let(:expected_apps) { { 'app1' => '123' } }
  let(:expected_uat_host) { 'uat.example.com' }
  let(:expected_uat_url) { "http://#{expected_uat_host}" }

  let(:time) { Time.current }
  let(:feature_review) { new_feature_review(expected_apps, expected_uat_url) }
  let(:feature_review_with_statuses) { instance_double(FeatureReviewWithStatuses) }

  subject(:query) { Queries::FeatureReviewQuery.new(feature_review, at: time) }

  before do
    allow(Repositories::BuildRepository).to receive(:new).and_return(build_repository)
    allow(Repositories::DeployRepository).to receive(:new).and_return(deploy_repository)
    allow(Repositories::ManualTestRepository).to receive(:new).and_return(manual_test_repository)
    allow(Repositories::TicketRepository).to receive(:new).and_return(ticket_repository)
    allow(Repositories::UatestRepository).to receive(:new).and_return(uatest_repository)
    allow(Repositories::ReleaseExceptionRepository).to receive(:new).and_return(release_exception_repository)

    allow(build_repository).to receive(:builds_for)
      .with(apps: expected_apps, at: time)
      .and_return(expected_builds)
    allow(deploy_repository).to receive(:deploys_for)
      .with(apps: expected_apps, server: expected_uat_host, at: time)
      .and_return(expected_deploys)
    allow(manual_test_repository).to receive(:qa_submission_for)
      .with(versions: expected_apps.values, at: time)
      .and_return(expected_qa_submission)
    allow(release_exception_repository).to receive(:release_exception_for)
      .with(versions: expected_apps.values, at: time)
      .and_return(expected_release_exception)
    allow(ticket_repository).to receive(:tickets_for_path)
      .with(feature_review.path, at: time)
      .and_return(expected_tickets)
    allow(uatest_repository).to receive(:uatest_for)
      .with(versions: expected_apps.values, server: expected_uat_host, at: time)
      .and_return(expected_uatest)
  end

  describe '#feature_review_with_statuses' do
    it 'returns a feature review with statuses' do
      expect(FeatureReviewWithStatuses).to receive(:new)
        .with(
          feature_review,
          builds: expected_builds,
          deploys: expected_deploys,
          qa_submission: expected_qa_submission,
          tickets: expected_tickets,
          release_exception: expected_release_exception,
          uatest: expected_uatest,
          at: time,
        )
        .and_return(feature_review_with_statuses)

      expect(query.feature_review_with_statuses).to eq(feature_review_with_statuses)
    end
  end
end
