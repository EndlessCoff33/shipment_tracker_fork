Feature:
  Developer prepares a Feature Review so that it can be attached to a ticket for a PO to use in acceptance.

Background:
  Given an application called "frontend"
  And an application called "backend"
  And an application called "mobile"
  And an application called "irrelevant"

@logged_in
Scenario: Preparing a Feature Review
  When I prepare a feature review for:
    | field name | content             |
    | frontend   | abc123456789        |
    | backend    | def123456789        |
    | uat_url    | http://www.some.url |
  Then I should see the feature review page with the applications:
    | app_name | version |
    | frontend | abc1234 |
    | backend  | def1234 |
  And I can see the UAT environment "http://www.some.url"

@logged_in
Scenario: Viewing User Acceptance Tests results on a Feature review
  Given a commit "#abc" by "Alice" is created for app "frontend"
  And a commit "#def" by "Bob" is created for app "backend"
  And commit "#abc" is deployed by "Alice" on server "uat.fundingcircle.com"
  And commit "#def" is deployed by "Bob" on server "uat.fundingcircle.com"
  And a developer prepares a review for UAT "uat.fundingcircle.com" with apps
    | app_name | version |
    | frontend | #abc    |
    | backend  | #def    |
  And User Acceptance Tests at version "abc123" which "passed" on server "uat.fundingcircle.com"
  And User Acceptance Tests at version "abc123" which "failed" on server "other-uat.fundingcircle.com"

  When I visit the feature review

  Then I should see a summary that includes
    | status  | title                 |
    | success | User Acceptance Tests |

  And I should see the results of the User Acceptance Tests with heading "success" and version "abc123"

@logged_in
Scenario: Viewing a feature review
  Given a ticket "JIRA-123" with summary "Urgent ticket" is started
  And a commit "#abc" by "Alice" is created for app "frontend"
  And a commit "#old" by "Bob" is created for app "backend"
  And a commit "#def" by "Bob" is created for app "backend"
  And a commit "#ghi" by "Carol" is created for app "mobile"
  And a commit "#xyz" by "Wendy" is created for app "irrelevant"
  And CircleCi "passes" for commit "#abc"
  And CircleCi "fails" for commit "#def"
  # Flaky tests, build retriggered.
  And CircleCi "passes" for commit "#def"
  And commit "#abc" is deployed by "Alice" on server "uat.fundingcircle.com"
  And commit "#old" is deployed by "Bob" on server "uat.fundingcircle.com"
  And commit "#def" is deployed by "Bob" on server "other-uat.fundingcircle.com"
  And commit "#xyz" is deployed by "Wendy" on server "uat.fundingcircle.com"
  And a developer prepares a review for UAT "uat.fundingcircle.com" with apps
    | app_name | version |
    | frontend | #abc    |
    | backend  | #def    |
    | mobile   | #ghi    |
  And adds the link to a comment for ticket "JIRA-123"

  When I visit the feature review

  Then I should see a summary with heading "danger" and content
    | status  | title                 |
    | warning | Test Results          |
    | failed  | UAT Environment       |
    | warning | QA Acceptance         |
    | warning | User Acceptance Tests |

  And I should only see the ticket
    | Key      | Summary       | Status      |
    | JIRA-123 | Urgent ticket | In Progress |

  And I should see the builds with heading "warning" and content
    | Status  | App      | Source   |
    | success | frontend | CircleCi |
    | success | backend  | CircleCi |
    | warning | mobile   |          |

  And I should see the deploys to UAT with heading "danger" and content
    | App      | Version | Correct |
    | frontend | #abc    | yes     |
    | backend  | #old    | no      |

Scenario: QA rejects and approves feature
  Given I am logged in as "foo@bar.com"
  And a developer prepares a review for UAT "uat.fundingcircle.com" with apps
    | app_name | version |
    | frontend | abc     |
    | backend  | def     |
  When I visit the feature review
  Then I should see the QA acceptance with heading "warning"

  When I "reject" the feature with comment "Not good enough"
  Then I should see the QA acceptance
    | status  | email       | comment         |
    | danger  | foo@bar.com | Not good enough |

  When I "accept" the feature with comment "Superb!"
  Then I should see the QA acceptance
    | status  | email       | comment |
    | success | foo@bar.com | Superb! |

@logged_in
Scenario: Feature review locks after the tickets get approved
  Given a ticket "JIRA-123" with summary "A ticket" is started
  Given a ticket "JIRA-124" with summary "A ticket" is started
  And a commit "#abc" by "Alice" is created for app "frontend"
  And CircleCi "passes" for commit "#abc"
  And commit "#abc" is deployed by "Alice" on server "uat.fundingcircle.com"
  And a developer prepares a review for UAT "uat.fundingcircle.com" with apps
    | app_name | version |
    | frontend | #abc    |
  And adds the link to a comment for ticket "JIRA-123"
  And adds the link to a comment for ticket "JIRA-124"

  When I visit the feature review
  And I "accept" the feature with comment "LGTM"

  Then I should see a summary with heading "success" and content
    | status  | title                 |
    | success | Test Results          |
    | success | UAT Environment       |
    | success | QA Acceptance         |
    | warning | User Acceptance Tests |

  When ticket "JIRA-123" is approved by "carol@fundingcircle.com" at "11:42:24"

  And CircleCi "fails" for commit "#abc"

  And I visit the feature review

  Then I should see a summary with heading "danger" and content
    | status  | title                 |
    | failed  | Test Results          |
    | success | UAT Environment       |
    | success | QA Acceptance         |
    | warning | User Acceptance Tests |

  And CircleCi "passes" for commit "#abc"

  When ticket "JIRA-124" is approved by "carol@fundingcircle.com" at "11:45:24"

  And CircleCi "fails" for commit "#abc"
  And a commit "#xyz" by "David" is created for app "frontend"
  And commit "#xyz" is deployed by "David" on server "uat.fundingcircle.com"
  And I "reject" the feature with comment "Shabby"

  And I visit the feature review

  Then I should see that the feature review is locked

  And a summary with heading "success" and content
    | status  | title                 |
    | success | Test Results          |
    | success | UAT Environment       |
    | success | QA Acceptance         |
    | warning | User Acceptance Tests |

  When ticket "JIRA-123" is rejected

  And I visit the feature review

  Then I should see that the feature review is not locked

  And a summary with heading "danger" and content
    | status  | title                 |
    | failed  | Test Results          |
    | failed  | UAT Environment       |
    | failed  | QA Acceptance         |
    | warning | User Acceptance Tests |
