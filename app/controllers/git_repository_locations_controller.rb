class GitRepositoryLocationsController < ApplicationController
  def index
    @repo_location_form = repo_location_form
    @git_repository_locations = GitRepositoryLocation.all.order(:name)
  end

  def create
    @git_repository_location = GitRepositoryLocation.new(git_repository_location_params)
    @repo_location_form = repo_location_form
    if @repo_location_form.valid? && @git_repository_location.save
      redirect_to :git_repository_locations
    else
      @git_repository_locations = GitRepositoryLocation.all
      flash.now[:error] = errors
      render :index
    end
  end

  private

  def errors
    if @git_repository_location.errors.empty?
      @repo_location_form.errors.full_messages.to_sentence
    else
      @git_repository_location.errors.full_messages.to_sentence
    end
  end

  def repo_location_form
    Forms::RepositoryLocationsForm.new(params.dig(:forms_repository_locations_form, :uri))
  end

  def git_repository_location_params
    params.require(:forms_repository_locations_form).permit(:uri)
  end
end
