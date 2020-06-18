package uk.gov.justice.hmpps.architecture.prison

import com.structurizr.model.Model

fun prisonModel(model: Model) {
  val nomis = NOMIS(model).system
  val ndh = NDH(model).system

  ndh.uses(nomis, "extract offender data")
}