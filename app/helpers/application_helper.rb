module ApplicationHelper
  OUTCOME_CLASSES = {
    "awaiting" => "bg-slate-100 text-slate-700",
    "in_progress" => "bg-sky-100 text-sky-800",
    "ghosted" => "bg-amber-100 text-amber-800",
    "rejection" => "bg-rose-100 text-rose-800",
    "offer" => "bg-emerald-100 text-emerald-800",
    "withdrawn" => "bg-slate-200 text-slate-700"
  }.freeze

  def outcome_badge(application)
    outcome = application.outcome
    tag.span(Application::OUTCOMES.fetch(outcome),
             class: "inline-block whitespace-nowrap rounded-full px-2 py-0.5 text-xs font-medium #{OUTCOME_CLASSES.fetch(outcome)}")
  end

  def kind_label(kind)
    Application::STAGE_LABELS.fetch(kind.to_s) { kind.to_s.humanize }
  end

  def short_time(time)
    time&.strftime("%d %b %Y")
  end

  def long_time(time)
    time&.strftime("%a %d %b %Y, %H:%M")
  end

  def nav_link(label, path, badge: nil)
    active = current_page?(path)
    classes = active ? "text-slate-900 font-medium" : "text-slate-600 hover:text-slate-900"
    link_to path, class: "text-sm #{classes}" do
      safe_join([ label, (tag.span(badge, class: "ml-1 rounded-full bg-amber-500 px-1.5 text-xs text-white") if badge.to_i.positive?) ])
    end
  end

  # Column header that toggles sorting while keeping the current filters.
  def sort_link(filter, column, label)
    arrow = filter.sort == column ? (filter.dir == "asc" ? " ↑" : " ↓") : ""
    params_for = filter.sort_params(column, request.query_parameters.symbolize_keys)
    link_to "#{label}#{arrow}", applications_path(params_for), class: "hover:text-slate-900"
  end

  def days_label(days)
    days.nil? ? "—" : "#{days.round}d"
  end
end
