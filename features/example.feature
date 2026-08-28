# DELETE THIS FILE once you have written your first real feature.
#
# It exists so the directory is not empty and so the shape is obvious. Keeping
# it after real features exist makes the suite lie about what is covered.

Feature: Example — replace me
  As Forge E2E Test's owner
  I want one worked example of the format
  So that the first real feature has a shape to copy

  # R0 — replace with the requirement this scenario proves
  Scenario: A scenario reads as one sentence per line
    Given the system is in a known starting state
    When the user does one specific thing
    Then one specific observable result follows

  # Cover the edges, not only the happy path.
  Scenario: The same behaviour at its boundary
    Given the system is at the edge of what is allowed
    When the user tries to go past it
    Then they are told clearly, and nothing changes
