import csv
import yaml
import click
import os
import subprocess
from typing import List
from github import Github, GithubException, Team

GITHUB_ORG = "splunk"
TEAM_PREFIX = "products-gdi"
# var to define maintainers for per repo team
PARENT_TEAM = "products-gdi-addons"
ADMIN_TEAM = os.environ["ADMIN_TEAM"]


class TeamManager:
    """
    Class to manage teams on GitHub based on csv definitions
    """

    def __init__(self, token: str, team_file: str, csvs: List[str]):
        self.g = Github(token)
        self.org = self.g.get_organization(GITHUB_ORG)
        self.repos = get_repos_from_csvs(csvs)
        self.team_file = team_file
        self.parent_team_id = self.org.get_team_by_slug(PARENT_TEAM).id

    def create_main_teams(self, all_repos_sync=True) -> None:
        """
        create GitHub teams based on yaml file with teams definitions and csv files
        with repositories definition.

        It adds repositories to teams with given permission.
        """
        with open(self.team_file) as f:
            teams = yaml.safe_load(f)

        for team, team_info in teams.items():
            click.echo(f"Working on team {team}")
            parent_team = self.org.get_team_by_slug(team_info["parent_team"]).id
            github_team = self.create_team(team, team_info["description"], parent_team=parent_team)
            self.add_admin_members(github_team)

            if all_repos_sync:
                repos_to_sync = self.repos
            else:
                existing_repos = [i.name for i in github_team.get_repos()]
                repos_to_sync = set(self.repos) - set(existing_repos)

            for repo in repos_to_sync:
                self.add_repository(github_team, repo, team_info["repo_permission"])

    def create_per_repo_teams(self) -> None:
        """
        Creates GitHub teams for every repository
        """
        for repo in self.repos:
            click.echo(f"Checking team for {repo}")
            team_name = f"{TEAM_PREFIX}-{repo}"
            github_team = self.get_team(team_name)
            if github_team is None:
                github_team = self.create_team(team_name, parent_team=self.parent_team_id)
                self.add_repository(github_team, repo, "push")
                self.add_admin_members(github_team)

    def get_admin_members(self) -> List[str]:
        """
        Returns members of admin team
        """
        team = self.org.get_team_by_slug(ADMIN_TEAM)
        members_on_github = team.get_members()
        return [member.login for member in members_on_github]

    def add_admin_members(self, team, role="maintainer") -> None:
        """
        Adds members as a maintainers to team
        """
        for member in self.get_admin_members():
            click.echo(f"Adding {member} as {role} to team {team.name}")
            team.add_membership(self.g.get_user(member), role)

    def create_team(self, team_name: str, description: str = "", parent_team=None) -> Team:
        """
        Creates GitHub team
        """
        github_team = self.get_team(team_name)
        if github_team is None:
            click.echo(f"Crating team {team_name}")
            github_team = self.org.create_team(
                team_name,
                privacy="closed",
                description=description)
        if parent_team is not None:
            # No support for adding parent team in PyGithub
            subprocess.Popen([f"gh api -X PATCH orgs/splunk/teams/{team_name} -F parent_team_id={parent_team}"], shell=True)
        return github_team

    def get_team(self, team_name: str) -> Team:
        """
        Returns GitHub team by name
        """
        try:
            github_team = self.org.get_team_by_slug(team_name)
        except GithubException:
            click.echo(f"Team {team_name} does not exist")
            github_team = None
        return github_team

    def add_repository(self, team: Team, repo: str, permission: str) -> None:
        """
        Adds repository to GitHub team with given permission
        """
        click.echo(f"Adding repository {repo} with permission {permission} to {team.name}")
        github_repo = self.org.get_repo(repo)
        if not team.has_in_repos(github_repo):
            team.add_to_repos(github_repo)
        repo_name_for_update = f"{GITHUB_ORG}/{repo}"
        if not team.update_team_repository(repo_name_for_update, permission):
            raise ValueError(f"Changing permission to {permission} for repository {repo} was not successful")


def get_repos_from_csvs(csvs: List[str]) -> List[str]:
    """
    returns list of repositories names from csv files
    """
    repos = []
    for csv in csvs:
        repos += get_repo_names_from_csv_file(csv)
    return repos


def get_repo_names_from_csv_file(path: str) -> List[str]:
    """
    parses csv with repositories definition and returns list with repo names
    """
    teams = []
    with open(path, newline='') as csvfile:
        reader = csv.DictReader(csvfile, fieldnames=["repo_name", "ta_name", "visibility", "description", "branch"])
        for row in reader:
            teams.append(row['repo_name'])
    return teams


@click.command()
@click.argument('token', nargs=1, type=click.STRING)
@click.argument('team_file', nargs=1, type=click.STRING)
@click.argument('repo_csvs', nargs=-1, type=click.Path())
def create_teams(token, team_file, repo_csvs):
    tm = TeamManager(token=token, team_file=team_file, csvs=repo_csvs)
    tm.create_main_teams()
    tm.create_per_repo_teams()


if __name__ == '__main__':
    create_teams()
