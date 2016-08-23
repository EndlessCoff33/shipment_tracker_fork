# frozen_string_literal: true
require 'rails_helper'

RSpec.describe Repositories::DeployRepository do
  subject(:repository) { Repositories::DeployRepository.new }

  describe '#table_name' do
    let(:active_record_class) { class_double(Snapshots::Deploy, table_name: 'the_table_name') }

    subject(:repository) { Repositories::DeployRepository.new(active_record_class) }

    it 'delegates to the active record class backing the repository' do
      expect(repository.table_name).to eq('the_table_name')
    end
  end

  describe '#apply' do
    let(:versions) { %w(abc def xyz jkl).map { |sha| expand_sha(sha) } }
    let(:environment) { 'production' }
    let(:defaults) {
      { app_name: 'frontend', server: 'test.com', deployed_by: 'Bob', environment: environment, locale: 'us' }
    }
    let(:expected_attrs) {
      {
        current_deploy: {
          'id' => a_value > 0,
          'app_name' => 'frontend',
          'server' => 'test.com',
          'version' => expand_sha('xyz'),
          'deployed_by' => 'Bob',
          'event_created_at' => '',
          'environment' => environment,
          'region' => 'us',
        },
        previous_deploy: nil,
      }
    }

    before do
      allow(DeployAlert).to receive(:auditable?).and_return(true)
    end

    it 'schedules a DeployAlertJob' do
      expect(DeployAlertJob).to receive(:perform_later).with(expected_attrs)

      repository.apply(build(:deploy_event,
        defaults.merge(version: expand_sha('xyz'), environment: 'production')))
    end

    context 'when in data maintenance mode' do
      before do
        allow(Rails.configuration).to receive(:data_maintenance_mode).and_return(true)
      end

      it 'does not schedule a DeployAlertJob' do
        expect(DeployAlertJob).not_to receive(:perform_later)
        repository.apply(build(:deploy_event,
          defaults.merge(version: expand_sha('xyz'), environment: 'production')))
      end
    end
  end

  describe '#deploys_for_versions' do
    let(:versions) { %w(abc def xyz jkl).map { |sha| expand_sha(sha) } }
    let(:environment) { 'production' }
    let(:defaults) {
      { app_name: 'frontend', server: 'test.com', deployed_by: 'Bob', environment: environment, locale: 'us' }
    }

    context 'when deploy events exist' do
      before do
        repository.apply(build(:deploy_event, defaults.merge(version: expand_sha('xyz'), environment: 'uat')))
        repository.apply(build(:deploy_event, defaults.merge(version: expand_sha('abc'))))
        repository.apply(build(:deploy_event, defaults.merge(version: expand_sha('abc'), deployed_by: 'Car')))
        repository.apply(build(:deploy_event, defaults.merge(version: expand_sha('def'))))
        repository.apply(build(:deploy_event, defaults.merge(version: expand_sha('ghi'))))
        repository.apply(build(:deploy_event, defaults.merge(version: expand_sha('jkl'), locale: 'gb')))
      end

      it 'returns all deploys for given version, environment and region' do
        expect(repository.deploys_for_versions(versions, environment: environment, region: 'us'))
          .to match_array([
            Deploy.new(defaults.merge(version: versions.first, deployed_by: 'Car', region: 'us')),
            Deploy.new(defaults.merge(version: versions.second, region: 'us')),
          ])
      end
    end

    context 'when no deploy exists' do
      it 'returns empty' do
        expect(repository.deploys_for_versions(versions, environment: environment, region: 'us')).to be_empty
      end
    end
  end

  describe '#deploys_for' do
    let(:apps) { { 'frontend' => expand_sha('abc') } }
    let(:server) { 'uat.fundingcircle.com' }

    let(:defaults) {
      {
        app_name: 'frontend',
        server: server,
        deployed_by: 'Bob',
        version: expand_sha('abc'),
        locale: 'gb',
        environment: 'uat',
      }
    }

    it 'projects last deploy' do
      repository.apply(build(:deploy_event, defaults.merge(version: expand_sha('abc'))))
      results = repository.deploys_for(apps: apps, server: server)
      expect(results).to eq([
        Deploy.new(defaults.merge(version: expand_sha('abc'), correct: true, region: 'gb')),
      ])

      repository.apply(build(:deploy_event, defaults.merge(version: expand_sha('def'))))
      results = repository.deploys_for(apps: apps, server: server)
      expect(results).to eq([
        Deploy.new(defaults.merge(version: expand_sha('def'), correct: false, region: 'gb')),
      ])
    end

    it 'is case insensitive when a repo name and the event app name do not match in case' do
      repository.apply(build(:deploy_event, defaults.merge(app_name: 'Frontend')))

      results = repository.deploys_for(apps: apps, server: server)
      expect(results).to eq([Deploy.new(defaults.merge(app_name: 'frontend', correct: true, region: 'gb'))])
    end

    it 'ignores the deploys event when it is for another server' do
      repository.apply(build(:deploy_event, defaults.merge(server: 'other.fundingcircle.com')))

      expect(repository.deploys_for(apps: apps, server: server)).to eq([])
    end

    it 'ignores the deploy event when it is for an app that is not under review' do
      repository.apply(build(:deploy_event, defaults.merge(app_name: 'irrelevant_app')))

      expect(repository.deploys_for(apps: apps, server: server)).to eq([])
    end

    it 'reports an incorrect version deployed to the UAT when event is for a different app version' do
      repository.apply(build(:deploy_event, defaults))
      expect(repository.deploys_for(apps: apps, server: server).map(&:correct)).to eq([true])

      repository.apply(build(:deploy_event, defaults.merge(version: expand_sha('def'))))
      expect(repository.deploys_for(apps: apps, server: server).map(&:correct)).to eq([false])
    end

    context 'with multiple apps' do
      let(:apps) { { 'frontend' => expand_sha('abc'), 'backend' => expand_sha('abc') } }

      it 'returns multiple deploys' do
        repository.apply(build(:deploy_event, defaults.merge(app_name: 'frontend')))
        repository.apply(build(:deploy_event, defaults.merge(app_name: 'backend')))

        expect(repository.deploys_for(apps: apps, server: server)).to match_array([
          Deploy.new(defaults.merge(app_name: 'frontend', correct: true, region: 'gb')),
          Deploy.new(defaults.merge(app_name: 'backend', correct: true, region: 'gb')),
        ])
      end
    end

    context 'with no apps' do
      let(:defaults) { { deployed_by: 'dj', environment: 'uat' } }
      it 'returns deploys for all apps to that server' do
        repository.apply(build(:deploy_event,
          defaults.merge(server: 'x.io', version: expand_sha('1'), app_name: 'a')))
        repository.apply(build(:deploy_event,
          defaults.merge(server: 'x.io', version: expand_sha('2'), app_name: 'b')))
        repository.apply(build(:deploy_event,
          defaults.merge(server: 'y.io', version: expand_sha('3'), app_name: 'c')))

        results = repository.deploys_for(server: 'x.io')

        expect(results).to match_array([
          Deploy.new(
            defaults.merge(
              app_name: 'a', server: 'x.io', version: expand_sha('1'), correct: false, region: 'us',
            ),
          ),
          Deploy.new(
            defaults.merge(
              app_name: 'b', server: 'x.io', version: expand_sha('2'), correct: false, region: 'us',
            ),
          ),
        ])
      end
    end

    context 'with at specified' do
      let(:defaults) { { server: 'x.io', deployed_by: 'dj', environment: 'uat' } }
      let(:time) { (Time.current - 4.hours).change(usec: 0) }
      it 'returns the state at that moment' do
        events = [
          build(:deploy_event,
            defaults.merge(version: expand_sha('abc'), app_name: 'app1', created_at: time)),
          build(:deploy_event, defaults.merge(server: 'y.io', app_name: 'app1', created_at: time + 1.hour)),
          build(:deploy_event,
            defaults.merge(version: expand_sha('def'), app_name: 'app2', created_at: time + 2.hours)),
          build(:deploy_event,
            defaults.merge(version: expand_sha('ghi'), app_name: 'app1', created_at: time + 3.hours)),
        ]

        events.each do |event|
          repository.apply(event)
        end

        results = repository.deploys_for(
          apps: {
            'app1' => expand_sha('abc'),
            'app2' => expand_sha('def'),
          },
          server: 'x.io',
          at: time + 1.second,
        )

        expect(results).to match_array([
          Deploy.new(app_name: 'app1',
                     server: 'x.io',
                     version: expand_sha('abc'),
                     deployed_by: 'dj',
                     region: 'us',
                     correct: true,
                     environment: 'uat',
                     event_created_at: time),
        ])
      end
    end
  end

  describe '#last_staging_deploy_for_version' do
    let(:version) { expand_sha('abc') }
    let(:defaults) { { app_name: 'frontend', deployed_by: 'Bob', locale: 'de', environment: 'uat' } }

    context 'when no deploy exist' do
      it 'returns nil' do
        expect(repository.last_staging_deploy_for_version(version)).to be nil
      end
    end

    context 'when no deploys exist for the version under review' do
      before do
        [
          build(:deploy_event, defaults.merge(server: 'a', environment: 'uat', version: expand_sha('def'))),
          build(:deploy_event, defaults.merge(server: 'b', environment: 'uat', version: expand_sha('ghi'))),
          build(:deploy_event,
            defaults.merge(server: 'c', environment: 'production', version: expand_sha('xyz'))),
        ].each do |deploy|
          repository.apply(deploy)
        end
      end

      it 'returns nil' do
        expect(repository.last_staging_deploy_for_version(version)).to be nil
      end
    end

    context 'when a deploy exists for the version under review' do
      before do
        [
          build(:deploy_event, defaults.merge(server: 'a', environment: 'uat', version: version)),
          build(:deploy_event, defaults.merge(server: 'b', environment: 'uat', version: version)),
          build(:deploy_event, defaults.merge(server: 'b', environment: 'uat', version: expand_sha('def'))),
          build(:deploy_event, defaults.merge(server: 'c', environment: 'production', version: version)),
        ].each do |deploy|
          repository.apply(deploy)
        end
      end

      it 'returns the latest non-production deploy for the version under review' do
        expect(repository.last_staging_deploy_for_version(version)).to eq(
          Deploy.new(defaults.merge(server: 'b', version: version, region: 'de')),
        )
      end

      it 'looks for any non-production environments' do
        repository.apply(
          build(:deploy_event, defaults.merge(server: 'c', environment: 'uat', version: version)),
        )

        expect(repository.last_staging_deploy_for_version(version)).to eq(
          Deploy.new(defaults.merge(server: 'c', version: version, region: 'de')),
        )
      end
    end
  end

  describe '#second_last_production_deploy' do
    let(:defaults) {
      {
        server: 'a',
        app_name: 'frontend',
        deployed_by: 'Bob',
        locale: 'gb',
        environment: 'production',
      }
    }

    context 'when no deploy exist' do
      it 'returns nil' do
        expect(repository.second_last_production_deploy('frontend', 'gb')).to be nil
      end
    end

    context 'when a deploy exists for the app and region' do
      before do
        [
          build(:deploy_event, defaults.merge(app_name: 'backend', version: expand_sha('ccc'))),
          build(:deploy_event, defaults.merge(version: expand_sha('bbb'))),
          build(:deploy_event, defaults.merge(app_name: 'backend', version: expand_sha('def'), locale: 'us')),
          build(:deploy_event, defaults.merge(app_name: 'backend', version: expand_sha('eee'))),
          build(:deploy_event, defaults.merge(version: expand_sha('ccc'))),
        ].each do |deploy|
          repository.apply(deploy)
        end
      end

      it 'returns the second latest production deploy for the app_name and region' do
        deploy = repository.second_last_production_deploy('backend', 'gb')
        expect(deploy.version).to eq expand_sha('ccc')
        expect(deploy.region).to eq 'gb'
      end
    end
  end
end

def expand_sha(sha)
  "#{sha}abcabcabcabcabcabcabcabcabcabcabcabcabc"[0..39]
end
