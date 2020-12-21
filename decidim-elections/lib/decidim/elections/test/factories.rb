# frozen_string_literal: true

require "decidim/core/test/factories"
require "decidim/forms/test/factories"

FactoryBot.define do
  sequence(:private_key) do
    JWT::JWK.new(OpenSSL::PKey::RSA.new(4096))
  end

  factory :elections_component, parent: :component do
    name { Decidim::Components::Namer.new(participatory_space.organization.available_locales, :elections).i18n_name }
    manifest_name { :elections }
    participatory_space { create(:participatory_process, :with_steps, organization: organization) }
  end

  factory :election, class: "Decidim::Elections::Election" do
    transient do
      organization { build(:organization) }
    end

    upcoming
    title { generate_localized_title }
    description { Decidim::Faker::Localized.wrapped("<p>", "</p>") { generate_localized_title } }
    end_time { 3.days.from_now }
    published_at { nil }
    blocked_at { nil }
    bb_status { nil }
    questionnaire
    component { create(:elections_component, organization: organization) }

    trait :upcoming do
      start_time { 1.day.from_now }
    end

    trait :started do
      start_time { 2.days.ago }
    end

    trait :ongoing do
      started
    end

    trait :finished do
      started
      end_time { 1.day.ago }
      blocked_at { Time.current }
    end

    trait :published do
      published_at { Time.current }
    end

    trait :complete do
      after(:build) do |election, _evaluator|
        election.questions << build(:question, :yes_no, election: election, weight: 1)
        election.questions << build(:question, :candidates, election: election, weight: 3)
        election.questions << build(:question, :projects, election: election, weight: 2)
        election.questions << build(:question, :nota, election: election, weight: 4)
      end
    end

    trait :ready_for_setup do
      transient do
        trustee_keys { 2.times.map { generate(:private_key).export.to_json } }
      end

      upcoming
      published
      complete

      after(:create) do |election, evaluator|
        evaluator.trustee_keys.each do |name, key|
          create(:trustee, :with_public_key, name: name, election: election, public_key: key)
        end
      end
    end

    trait :created do
      ready_for_setup
      blocked_at { start_time - 1.day }

      start_time { 1.hour.from_now }
      bb_status { "key_ceremony" }

      after(:create) do |election|
        trustees_participatory_spaces = Decidim::Elections::TrusteesParticipatorySpace.where(participatory_space: election.component.participatory_space)
        election.trustees << trustees_participatory_spaces.map(&:trustee)
      end
    end

    trait :ready do
      created
      bb_status { "ready" }
    end

    trait :vote do
      created
      ongoing
      bb_status { "vote" }
    end

    trait :results do
      vote
      finished
      bb_status { "results" }

      after(:build) do |election|
        election.questions.each do |question|
          question.answers.each do |answer|
            answer.votes_count = Faker::Number.number(digits: 1)
          end
        end
      end
    end

    trait :results_published do
      results
      bb_status { "results_published" }
    end

    trait :bb_test_election do
      id { 10_000 + Decidim::Elections::Election.bb_statuses.keys.index(bb_status) }
    end
  end

  factory :question, class: "Decidim::Elections::Question" do
    transient do
      more_information { false }
      answers { 3 }
    end

    election
    title { generate_localized_title }
    description { Decidim::Faker::Localized.wrapped("<p>", "</p>") { generate_localized_title } }
    min_selections { 1 }
    max_selections { 1 }
    weight { Faker::Number.number(digits: 1) }
    random_answers_order { true }

    trait :complete do
      after(:build) do |question, evaluator|
        overrides = { question: question }
        overrides[:description] = nil unless evaluator.more_information
        question.answers = build_list(:election_answer, evaluator.answers, overrides)
      end
    end

    trait :yes_no do
      complete
      random_answers_order { false }
    end

    trait :candidates do
      complete
      max_selections { 6 }
      answers { 10 }
    end

    trait :projects do
      complete
      max_selections { 3 }
      answers { 6 }
      more_information { true }
    end

    trait :nota do
      complete
      max_selections { 4 }
      answers { 8 }
      min_selections { 0 }
    end

    trait :with_votes do
      after(:build) do |question, evaluator|
        overrides = { question: question }
        overrides[:description] = nil unless evaluator.more_information
        question.answers = build_list(:election_answer, evaluator.answers, :with_votes, overrides)
      end
    end
  end

  factory :election_answer, class: "Decidim::Elections::Answer" do
    question
    title { generate_localized_title }
    description { Decidim::Faker::Localized.wrapped("<p>", "</p>") { generate_localized_title } }
    weight { Faker::Number.number(digits: 1) }
    selected { false }
    votes_count { 0 }

    trait :with_votes do
      votes_count { Faker::Number.number(digits: 1) }
    end
  end

  factory :trustee, class: "Decidim::Elections::Trustee" do
    transient do
      election { nil }
      organization { election&.component&.participatory_space&.organization || create(:organization) }
    end

    public_key { nil }
    user { build(:user, organization: organization) }

    trait :considered do
      after(:build) do |trustee, evaluator|
        trustee.trustees_participatory_spaces << build(:trustees_participatory_space, trustee: trustee, election: evaluator.election, organization: evaluator.organization)
      end
    end

    trait :with_elections do
      after(:build) do |_election, evaluator|
        trustee.elections << build(:election, :upcoming, organization: evaluator.organization)
      end
    end

    trait :with_public_key do
      considered
      name { Faker::Name.name }
      public_key { generate(:private_key).export.to_json }
    end
  end

  factory :trustees_participatory_space, class: "Decidim::Elections::TrusteesParticipatorySpace" do
    transient do
      organization { election&.component&.participatory_space&.organization || create(:organization) }
      election { nil }
    end
    participatory_space { election&.component&.participatory_space || create(:participatory_process, organization: organization) }
    considered { true }
    trustee { create(:trustee, organization: organization) }

    trait :trustee_ready do
      association :trustee, :with_public_key
    end
  end
end
