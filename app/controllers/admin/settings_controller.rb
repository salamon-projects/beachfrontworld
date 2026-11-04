module Admin
  class SettingsController < BaseController
    def edit
      @setting = SiteSetting.current
    end

    def update
      @setting = SiteSetting.current
      before = @setting.max_walk_m
      if @setting.update(params.expect(site_setting: %i[max_walk_m]))
        notice = "Settings saved."
        if @setting.max_walk_m > before
          RemeasureWalksJob.perform_later
          notice += " Walks are being measured again up to #{@setting.max_walk_m} m in the background."
        end
        redirect_to edit_admin_settings_path, notice:
      else
        render :edit, status: :unprocessable_content
      end
    end
  end
end
