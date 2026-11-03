module Admin
  class PropertiesController < BaseController
    VIEWS = {
      "listed" => "On the site",
      "unlisted" => "Nothing nearby",
      "hidden" => "Hidden",
      "conflicts" => "OTA claim conflicts",
      "mismatch" => "Position mismatch",
      "missing" => "Not in OSM",
      "all" => "All"
    }.freeze

    before_action :set_property, only: %i[show edit update destroy hide unhide reclassify]

    def index
      @view = params[:view].presence_in(VIEWS.keys) || "listed"
      @destinations = Destination.ordered
      # Remembered so a property page can step through this list.
      session[:admin_property_list] = { "view" => @view, "destination_id" => params[:destination_id].presence,
                                        "q" => params[:q].presence }.compact
      scope = list_scope(session[:admin_property_list]).preload(:destination, :listings, :waterfront)
      @pagy, @properties = pagy(scope.by_waterfront, limit: 50)
      return if redirect_past_last_page(@pagy)

      @untracked_providers = Affiliate::Provider.all.values.reject(&:tracking_configured?)
    end

    def show
      @list = session[:admin_property_list].presence || { "view" => "all" }
      @list_nav = @property.neighbors_in(list_scope(@list))
      @walks = @property.walks.joins(:landmark).preload(:landmark).order(:walk_m).limit(15)
    end

    def new
      @property = Property.new(destination_id: params[:destination_id], kind: "hotel")
    end

    def create
      @property = Property.new(property_params.merge(reviewed_at: Time.current))
      if @property.save
        measure
        redirect_to admin_property_path(@property), notice: "Property created and measured."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit; end

    def update
      if @property.update(property_params.merge(reviewed_at: Time.current))
        measure if @property.saved_change_to_lonlat?
        redirect_to admin_property_path(@property), notice: "Property updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @property.destroy!
      redirect_to admin_properties_path, notice: "#{@property.name} deleted."
    end

    def hide
      @property.update!(hidden_at: Time.current, reviewed_at: Time.current)
      redirect_back_or_to admin_property_path(@property), notice: "#{@property.name} is hidden from the site."
    end

    def unhide
      @property.update!(hidden_at: nil, reviewed_at: Time.current)
      redirect_back_or_to admin_property_path(@property), notice: "#{@property.name} is no longer hidden."
    end

    def reclassify
      measure
      redirect_to admin_property_path(@property),
                  notice: "Measured again: #{t("waterfront.categories.#{@property.reload.waterfront.category}")}."
    end

    private

    def set_property
      @property = Property.find_by!(slug: params[:id])
    end

    def property_params
      params.expect(property: %i[destination_id name slug kind stars address website latitude longitude])
    end

    # Waterfront result and walks, right away rather than in the background.
    def measure
      Waterfront::Classification.new(@property).call
      Walks::Measurement.new(@property.destination).call(property_ids: [ @property.id ])
    end

    # The properties of an index view with its filters, unordered.
    def list_scope(list)
      scope = scoped_by_view(Property.left_joins(:waterfront), list["view"])
      scope = scope.where(destination_id: list["destination_id"]) if list["destination_id"].present?
      scope = scope.where("properties.name ILIKE ?", "%#{Property.sanitize_sql_like(list['q'])}%") if list["q"].present?
      scope
    end

    def scoped_by_view(scope, view)
      case view
      when "listed" then scope.merge(Property.published)
      when "unlisted" then scope.where(hidden_at: nil, osm_missing_since: nil).where.not(id: Property.published.select(:id))
      when "hidden" then scope.hidden
      when "conflicts" then scope.beachfront_claim_conflicts
      when "mismatch" then scope.with_coordinate_mismatch
      when "missing" then scope.missing_from_osm
      else scope
      end
    end
  end
end
