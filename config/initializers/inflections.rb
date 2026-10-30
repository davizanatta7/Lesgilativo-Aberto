# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.irregular "parlamentar", "parlamentares"
  inflect.irregular "proposta", "propostas"
  inflect.irregular "autoria", "autorias"
  inflect.irregular "despesa", "despesas"
  inflect.irregular "votacao", "votacoes"
  inflect.irregular "voto_parlamentar", "votos_parlamentares"
end

# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end
