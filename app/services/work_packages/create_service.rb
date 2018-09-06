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

class WorkPackages::CreateService
  include ::WorkPackages::Shared::UpdateAncestors
  include ::Shared::ServiceContext

  attr_accessor :user,
                :work_package,
                :contract

  def initialize(user:, contract: WorkPackages::CreateContract)
    self.user = user
    self.contract = contract
  end

  def call(attributes: {},
           work_package: WorkPackage.new,
           send_notifications: true)
    in_context(send_notifications) do
      create(attributes, work_package)
    end
  end

  protected

  def create(attributes, work_package)

    result = set_attributes(attributes, work_package)

    result.success &&= work_package.save

    if result.success?
      result.merge!(reschedule_related(work_package))

      update_ancestors_all_attributes(result.all_results).each do |ancestor_result|
        result.merge!(ancestor_result)
      end
    else
      result.success = false
    end

    if work_package.attributes['type_id'] == 3
      wp_model_epic = ActionController::Parameters.new({
                  work_package: {
                    status_id: 1,
                    priority_id: 8, 
                    author_id: 1, 
                    lock_version: 0, 
                    done_ratio: 0,
                    type_id: 5, 
                    position: 1
                }
            })
      wp_model_task = ActionController::Parameters.new({
                  work_package: {
                    status_id: 1,
                    priority_id: 8, 
                    author_id: 1, 
                    lock_version: 0, 
                    done_ratio: 0,
                    type_id: 1, 
                    position: 1
                }
            })
      
      parent_id = work_package.attributes['id']
      project_id = work_package.attributes['project_id']
      project = Project.find(project_id)
      wp_due_date = work_package.attributes['due_date']
      d_d = wp_due_date
      wp_start_date = work_package.attributes['start_date']
      s_d = wp_start_date
      
      if wp_start_date.mday < 11
        s_d = s_d.at_beginning_of_month
      elsif wp_start_date.mday < 21
        s_d = s_d.at_beginning_of_month + 10
      else
        s_d = s_d.at_beginning_of_month + 20
      end
      if wp_due_date.mday < 11
        d_d = d_d.at_beginning_of_month + 9
      elsif wp_due_date.mday < 21
        d_d = d_d.at_beginning_of_month + 19
      else
        d_d = d_d.at_beginning_of_month.next_month - 1 
      end
      versions = project.versions.where("start_date >= ?", s_d)
                                  .where("effective_date <= ?", d_d)
                                  .order(:id)
      versions.reverse_each do |version|
        start_date = version['start_date']
        due_date = version['effective_date']
        days_count = due_date.mday - start_date.mday
        fixed_version_id = version['id']
        subject = version['name'] + " " + work_package['subject']
        permitted = wp_model_epic.require(:work_package).permit([:status_id, :type_id, :priority_id, :author_id, :lock_version, :done_ratio, :position])
                                                   .merge(parent_id: parent_id, subject: subject, project_id: project_id, due_date: due_date, start_date: start_date, fixed_version_id: fixed_version_id)
        wp_epic = WorkPackage.new
        wp_epic.attributes = permitted
        wp_epic.save
        parent_id1 = wp_epic.attributes['id']
        for i in 0..days_count
          date = start_date + i
          subject1 = "Отчет за " + date.strftime("%d/%m/%Y")
          permitted1 = wp_model_task.require(:work_package).permit([:status_id, :type_id, :priority_id, :author_id, :lock_version, :done_ratio, :position])
                                                   .merge(parent_id: parent_id1, subject: subject1, project_id: project_id, due_date: date, start_date: date)
          wp_task = WorkPackage.new
          wp_task.attributes = permitted1
          wp_task.save
        end
      end
    end
    result
  end

  def set_attributes(attributes, wp)
    WorkPackages::SetAttributesService
      .new(user: user,
           work_package: wp,
           contract: contract)
      .call(attributes)
  end

  def reschedule_related(work_package)
    result = WorkPackages::SetScheduleService
             .new(user: user,
                  work_package: work_package)
             .call

    result.self_and_dependent.each do |r|
      if !r.result.save
        result.success = false
        r.errors = r.result.errors
      end
    end

    result
  end
end
