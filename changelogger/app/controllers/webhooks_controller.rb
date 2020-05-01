class WebhooksController < ApplicationController
  WEBHOOK_HEADERS = %w(HTTP_USER_AGENT CONTENT_TYPE HTTP_X_GITHUB_EVENT HTTP_X_GITHUB_DELIVERY HTTP_X_HUB_SIGNATURE)

  before_action :verify_event_type!

  def create
    return unless closed?
    return unless merged?
    return unless changelog_enabled?

    create_changelog_entry
  end

  private

  def verify_event_type!
    type = request.headers["HTTP_X_GITHUB_EVENT"]
    return if type == "pull_request"
    render(status: 422, json: "unallowed event type: #{type}")
  end

  def closed?
    params["webhook"]["action"] == "closed"
  end

  def merged?
    !!params["pull_request"]["merged"]
  end

  def changelog_enabled?
    params["pull_request"]["labels"].any? do |label|
      label["name"] == "documentation"
    end
  end

  def octokit
    @octokit ||= Octokit::Client.new(access_token: Changelogger::Application.credentials.github_personal_access_token)
  end

  def repo
    params["repository"]["full_name"]
  end

  def change_description
    body = params["pull_request"]["body"]
    if matches = body.match(/<changes>(.*)<\/changes>/)
      matches.captures.first.strip
    else
      params["pull_request"]["title"]
    end
  end

  def diff_url
    params["pull_request"]["diff_url"]
  end

  def pr_url
    params["pull_request"]["html_url"]
  end

  def author_name
    params["pull_request"]["user"]["login"]
  end

  def author_url
    params["pull_request"]["user"]["html_url"]
  end

  def author_avatar
    params["pull_request"]["user"]["avatar_url"]
  end

  def format_changes
    <<-ENTRY
# #{Time.now.utc.to_s}

By: ![avatar](#{author_avatar}&s=50) [#{author_name}](#{author_url})

#{change_description}

[[diff](#{diff_url})][[pull request](#{pr_url})]
* * *

    ENTRY
  end

  def default_frontmatter
    <<-FRONTMATTER
---
layout: default
title: Home
nav_order: 1
description: "The Changelog"
permalink: /
---

    FRONTMATTER
  end

  def get_file(repo)
    response = octokit.contents(repo, path: "docs/index.md")
    [Base64.decode64(response["content"]), response["sha"]]
  rescue
    nil
  end

  def create_changelog_entry
    content, sha = get_file(repo)

    if content
      octokit.update_contents(repo,
                                 "docs/index.md",
                                 "New changelog entry",
                                 sha,
                                 content + format_changes)
    else
      octokit.create_contents(repo,
                                 "docs/index.md",
                                 "New changelog entry",
                                 default_frontmatter + format_changes)
    end
  end
end
