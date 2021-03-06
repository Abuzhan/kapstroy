#-- encoding: UTF-8
#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2017 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2017 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.rdoc for more details.
#++

class ProjectsController < ApplicationController
  menu_item :overview
  menu_item :roadmap, only: :roadmap
  menu_item :settings, only: :settings

  helper :timelines

  before_action :disable_api
  before_action :find_project, except: [:index, :level_list, :new, :create]
  before_action :authorize, only: [
    :show, :settings, :edit, :update, :modules, :types, :custom_fields
  ]
  before_action :authorize_global, only: [:new, :create]
  before_action :require_admin, only: [:archive, :unarchive, :destroy, :destroy_info]
  before_action :jump_to_project_menu_item, only: :show
  before_action :load_project_settings, only: :settings
  before_action :determine_base

  accept_key_auth :index, :level_list, :show, :create, :update, :destroy

  include SortHelper
  include PaginationHelper
  include CustomFieldsHelper
  include QueriesHelper
  include RepositoriesHelper
  include ProjectsHelper

  # Lists visible projects
  def index
    query = load_query
    set_sorting(query)

    unless query.valid?
      flash[:error] = query.errors.full_messages
    end

    @projects = load_projects query
    @custom_fields = ProjectCustomField.visible(User.current)

    respond_to do |format|
      format.atom do
        head(:gone)
      end
      format.html do
        render action: :index
      end
    end
  end

  current_menu_item :index do
    :list_projects
  end

  def new
    @issue_custom_fields = WorkPackageCustomField.order("#{CustomField.table_name}.position")
    @types = ::Type.all
    @project = Project.new
    @project.parent = Project.find(params[:parent_id]) if params[:parent_id]
    @project.attributes = permitted_params.project if params[:project].present?
  end

  current_menu_item :new do
    :new_project
  end

  def create
    @issue_custom_fields = WorkPackageCustomField.order("#{CustomField.table_name}.position")
    @types = ::Type.all
    @project = Project.new
    @project.attributes = permitted_params.project
    project_save_success = false
    version_save_success = true

    project_start_date = Date.strptime(params['project']['custom_field_values']['14'], '%Y-%m-%d')
    project_end_date = Date.strptime(params['project']['custom_field_values']['15'], '%Y-%m-%d')

    if validate_start_date_before_effective_date_for_version(project_start_date, project_end_date)
      if @project.save
        project_save_success = true
      end
    else
      flash.now[:error] = "Invalid Dates"
    end

    
    if params['project'].has_key?('parent_id') && project_save_success
      if params['project']['parent_id'] != ""
        
        

        version_model = ActionController::Parameters.new({
                  version: {
                    status: "open",
                    sharing: "none"
                }
            })

        #Creating decades for first month of contract
        if project_start_date.mday < 11
          decs_in_first = 3

          dec_name1 = "Декада 1"
          dec_name2 = "Декада 2"
          dec_name3 = "Декада 3"

          start_date1 = project_start_date.at_beginning_of_month
          start_date2 = start_date1 + 10
          start_date3 = start_date2 + 10

          effective_date1 = start_date1 + 9
          effective_date2 = start_date2 + 9
          effective_date3 = project_start_date.at_beginning_of_month.next_month - 1

          permitted1 = version_model.require(:version).permit([:status, :sharing]).merge(name: dec_name1, effective_date: effective_date1, start_date: start_date1, project_id: @project.id)
          permitted2 = version_model.require(:version).permit([:status, :sharing]).merge(name: dec_name2, effective_date: effective_date2, start_date: start_date2, project_id: @project.id)
          permitted3 = version_model.require(:version).permit([:status, :sharing]).merge(name: dec_name3, effective_date: effective_date3, start_date: start_date3, project_id: @project.id)

          version_save_success = create_version(permitted1)
          version_save_success = create_version(permitted2)
          version_save_success = create_version(permitted3)

        elsif project_start_date.mday < 21
          decs_in_first = 2
          
          dec_name1 = "Декада 1"
          dec_name2 = "Декада 2"
          
          start_date1 = project_start_date.at_beginning_of_month + 10
          start_date2 = start_date1 + 10
          
          effective_date1 = start_date1 + 9
          effective_date2 = project_start_date.at_beginning_of_month.next_month - 1
          
          permitted1 = version_model.require(:version).permit([:status, :sharing]).merge(name: dec_name1, effective_date: effective_date1, start_date: start_date1, project_id: @project.id)
          permitted2 = version_model.require(:version).permit([:status, :sharing]).merge(name: dec_name2, effective_date: effective_date2, start_date: start_date2, project_id: @project.id)
          
          version_save_success = create_version(permitted1)
          version_save_success = create_version(permitted2)

        else
          decs_in_first = 1

          dec_name1 = "Декада 1"
          start_date1 = project_start_date.at_beginning_of_month + 20
          effective_date1 = project_start_date.at_beginning_of_month.next_month - 1
          permitted1 = version_model.require(:version).permit([:status, :sharing]).merge(name: dec_name1, effective_date: effective_date1, start_date: start_date1, project_id: @project.id)
          version_save_success = create_version(permitted1)

        end

        #Declaring some constants before generating rest of decades
        if (project_end_date.year != project_start_date.year) || (project_end_date.month != project_start_date.month)
          months_between = (project_end_date.year*12 + project_end_date.month) - (project_start_date.year*12 + project_start_date.month) - 1
          total_decades_so_far = decs_in_first + months_between * 3
          decade_counter = decs_in_first + 1
          month_var = project_start_date

          #Loop for creating decades for every middle month
          for i in 1..months_between
            version_model = ActionController::Parameters.new({
                    version: {
                      status: "open",
                      sharing: "none"
                  }
              })
    
            dec_name1 = "Декада " + decade_counter.to_s
            dec_name2 = "Декада " + (decade_counter+1).to_s
            dec_name3 = "Декада " + (decade_counter+2).to_s

            start_date1 = month_var.at_beginning_of_month.next_month
            start_date2 = start_date1 + 10
            start_date3 = start_date2 + 10
            
            effective_date1 = start_date1 + 9
            effective_date2 = start_date2 + 9
            effective_date3 = month_var.at_beginning_of_month.next_month.next_month - 1

            permitted1 = version_model.require(:version).permit([:status, :sharing]).merge(name: dec_name1, effective_date: effective_date1, start_date: start_date1, project_id: @project.id)
            version_save_success = create_version(permitted1)

            permitted2 = version_model.require(:version).permit([:status, :sharing]).merge(name: dec_name2, effective_date: effective_date2, start_date: start_date2, project_id: @project.id)
            version_save_success = create_version(permitted2)

            permitted3 = version_model.require(:version).permit([:status, :sharing]).merge(name: dec_name3, effective_date: effective_date3, start_date: start_date3, project_id: @project.id)
            version_save_success = create_version(permitted3)

            month_var = month_var.next_month
            decade_counter += 3
          end

          #Creating decades for last month of contract
          if project_end_date.mday < 11

            dec_name1 = "Декада " + (total_decades_so_far+1).to_s
            start_date1 = project_end_date.at_beginning_of_month
            effective_date1 = start_date1 + 9
            permitted1 = version_model.require(:version).permit([:status, :sharing]).merge(name: dec_name1, effective_date: effective_date1, start_date: start_date1, project_id: @project.id)
            version_save_success = create_version(permitted1)

          elsif project_end_date.mday < 21

            dec_name1 = "Декада " + (total_decades_so_far+1).to_s
            dec_name2 = "Декада " + (total_decades_so_far+2).to_s
            
            start_date1 = project_end_date.at_beginning_of_month
            start_date2 = start_date1 + 10
            
            effective_date1 = start_date1 + 9
            effective_date2 = start_date2 + 9
            
            permitted1 = version_model.require(:version).permit([:status, :sharing]).merge(name: dec_name1, effective_date: effective_date1, start_date: start_date1, project_id: @project.id)
            permitted2 = version_model.require(:version).permit([:status, :sharing]).merge(name: dec_name2, effective_date: effective_date2, start_date: start_date2, project_id: @project.id)
            
            version_save_success = create_version(permitted1)
            version_save_success = create_version(permitted2)

          else

            dec_name1 = "Декада " + (total_decades_so_far+1).to_s
            dec_name2 = "Декада " + (total_decades_so_far+2).to_s
            dec_name3 = "Декада " + (total_decades_so_far+3).to_s
            
            start_date1 = project_end_date.at_beginning_of_month
            start_date2 = start_date1 + 10
            start_date3 = start_date2 + 10
            
            effective_date1 = start_date1 + 9
            effective_date2 = start_date2 + 9
            effective_date3 = project_end_date.at_beginning_of_month.next_month - 1
            
            permitted1 = version_model.require(:version).permit([:status, :sharing]).merge(name: dec_name1, effective_date: effective_date1, start_date: start_date1, project_id: @project.id)
            permitted2 = version_model.require(:version).permit([:status, :sharing]).merge(name: dec_name2, effective_date: effective_date2, start_date: start_date2, project_id: @project.id)
            permitted3 = version_model.require(:version).permit([:status, :sharing]).merge(name: dec_name3, effective_date: effective_date3, start_date: start_date3, project_id: @project.id)

            version_save_success = create_version(permitted1)
            version_save_success = create_version(permitted2)
            version_save_success = create_version(permitted3)
          end
        end
      end
    end

    if validate_parent_id && project_save_success && version_save_success 
      @project.set_allowed_parent!(params['project']['parent_id'])
      add_current_user_to_project_if_not_admin(@project)
      if params['project'].has_key?('parent_id') && params['project']['parent_id'] != ""
        respond_to do |format|
          format.html do
            flash[:notice] = l(:notice_successful_create)
            redirect_work_packages_or_overview
          end
        end
      else
        respond_to do |format|
          format.html do
            flash[:notice] = l(:notice_successful_create)
            redirect_settings_or_overview
          end
        end
      end
    else
      respond_to do |format|
        format.html do render action: 'new' end
      end
    end

  end

  def validate_start_date_before_effective_date_for_version(start_date, effective_date)
    if effective_date && start_date && effective_date < start_date
      return false
    else
      return true
    end
  end

  def create_version(permitted)
    @version = @project.versions.build
    @version.attributes = permitted
    if @version.save
      return true
    else
      return false
    end
  end

  # Show @project
  def show
    @users_by_role = @project.users_by_role
    @subprojects = @project.children.visible
    @news = @project.news.limit(5).includes(:author, :project).order("#{News.table_name}.created_on DESC")
    @types = @project.rolled_up_types

    cond = @project.project_condition(Setting.display_subprojects_work_packages?)

    @open_issues_by_type = WorkPackage
                           .visible.group(:type)
                           .includes(:project, :status, :type)
                           .where(["(#{cond}) AND #{Status.table_name}.is_closed=?", false])
                           .references(:projects, :statuses, :types)
                           .count
    @total_issues_by_type = WorkPackage
                            .visible.group(:type)
                            .includes(:project, :status, :type)
                            .where(cond)
                            .references(:projects, :statuses, :types)
                            .count

    respond_to do |format|
      format.html
    end
  end

  def settings
    @altered_project ||= @project
  end

  def edit; end

  def update
    @altered_project = Project.find(@project.id)

    @altered_project.attributes = permitted_params.project
    if validate_parent_id && @altered_project.save
      if params['project'].has_key?('parent_id')
        @altered_project.set_allowed_parent!(params['project']['parent_id'])
      end
      respond_to do |format|
        format.html do
          flash[:notice] = l(:notice_successful_update)
          redirect_to action: 'settings', id: @altered_project
        end
      end
      OpenProject::Notifications.send('project_updated', project: @altered_project)
    else
      respond_to do |format|
        format.html do
          load_project_settings
          render action: 'settings'
        end
      end
    end
  end

  def update_identifier
    @project.attributes = permitted_params.project

    if @project.save
      respond_to do |format|
        format.html do
          flash[:notice] = l(:notice_successful_update)
          redirect_to action: 'settings', id: @project
        end
      end
      OpenProject::Notifications.send('project_renamed', project: @project)
    else
      respond_to do |format|
        format.html do
          load_project_settings
          render action: 'identifier'
        end
      end
    end
  end

  def types
    if UpdateProjectsTypesService.new(@project).call(permitted_params.projects_type_ids)
      flash[:notice] = l('notice_successful_update')
    else
      flash[:error] = @project.errors.full_messages
    end

    redirect_to settings_project_path(@project.identifier, tab: 'types')
  end

  def modules
    @project.enabled_module_names = permitted_params.project[:enabled_module_names]
    flash[:notice] = l(:notice_successful_update)
    redirect_to action: 'settings', id: @project, tab: 'modules'
  end

  def custom_fields
    Project.transaction do
      @project.work_package_custom_field_ids = permitted_params.project[:work_package_custom_field_ids]
      if @project.save
        flash[:notice] = t(:notice_successful_update)
      else
        flash[:error] = t(:notice_project_cannot_update_custom_fields,
                          errors: @project.errors.full_messages.join(', '))
        raise ActiveRecord::Rollback
      end
    end
    redirect_to action: 'settings', id: @project, tab: 'custom_fields'
  end

  def archive
    flash[:error] = l(:error_can_not_archive_project) unless @project.archive
    redirect_to(url_for(controller: '/projects', action: 'index', status: params[:status]))
  end

  def unarchive
    @project.unarchive if !@project.active?
    redirect_to(url_for(controller: '/projects', action: 'index', status: params[:status]))
  end

  # Delete @project
  def destroy
    @project_to_destroy = @project

    OpenProject::Notifications.send('project_deletion_imminent', project: @project_to_destroy)
    @project_to_destroy.destroy
    respond_to do |format|
      format.html do
        flash[:notice] = l(:notice_successful_delete)
        redirect_to controller: '/admin', action: 'projects'
      end
    end

    hide_project_in_layout
  end

  def destroy_info
    @project_to_destroy = @project

    hide_project_in_layout
  end

  private

  def find_optional_project
    return true unless params[:id]
    @project = Project.find(params[:id])
    authorize
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def redirect_work_packages_or_overview
    return if redirect_to_project_menu_item(@project, :work_packages)

    redirect_to controller: '/projects', action: 'show', id: @project
  end

  def redirect_settings_or_overview
    return if redirect_to_project_menu_item(@project, :settings)

    redirect_to controller: '/projects', action: 'show', id: @project
  end

  def jump_to_project_menu_item
    if params[:jump]
      # try to redirect to the requested menu item
      redirect_to_project_menu_item(@project, params[:jump]) && return
    end
  end

  def load_project_settings
    @issue_custom_fields = WorkPackageCustomField.order("#{CustomField.table_name}.position")
    @category ||= Category.new
    @member ||= @project.members.new
    @types = ::Type.all
    @repository ||= @project.repository
    @wiki ||= @project.wiki
  end

  def hide_project_in_layout
    @project = nil
  end

  def add_current_user_to_project_if_not_admin(project)
    unless User.current.admin?
      r = Role.givable.find_by(id: Setting.new_project_user_role_id.to_i) || Role.givable.first
      m = Member.new do |member|
        member.user = User.current
        member.role_ids = [r].map(&:id) # member.roles = [r] fails, this works
      end
      project.members << m
    end
  end

  def load_query
    @query = ParamsToQueryService.new(Project, current_user).call(params)

    # Set default filter on status no filter is provided.
    if !params[:filters]
      @query.where('status', '=', Project::STATUS_ACTIVE.to_s)
    end

    # Order lft if no order is provided.
    if !params[:sortBy]
      @query.order(lft: :asc)
    end

    @query
  end

  def filter_projects_by_permission(projects)
    # Cannot simply use .visible here as it would
    # filter out archived projects for everybody.
    if User.current.admin?
      projects
    else
      projects.visible
    end
  end

  protected

  def determine_base
    @base = if params[:project_type_id]
              ProjectType.find(params[:project_type_id]).projects
            else
              Project
            end
  end

  def set_sorting(query)
    orders = query.orders.select(&:valid?).map { |o| [o.attribute.to_s, o.direction.to_s] }

    sort_clear
    sort_init orders
    sort_update orders.map(&:first)
  end

  def load_projects(query)
    projects = query
               .results
               .with_required_storage
               .with_latest_activity
               .includes(:custom_values, :enabled_modules)
               .page(page_param)
               .per_page(per_page_param)

    filter_projects_by_permission projects
  end

  # Validates parent_id param according to user's permissions
  # TODO: move it to Project model in a validation that depends on User.current
  def validate_parent_id
    return true if User.current.admin?
    parent_id = permitted_params.project && params[:project][:parent_id]
    if parent_id || @project.new_record?
      parent = parent_id.blank? ? nil : Project.find_by(id: parent_id.to_i)
      unless @project.allowed_parents.include?(parent)
        @project.errors.add :parent_id, :invalid
        return false
      end
    end
    true
  end
end
