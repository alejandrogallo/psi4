/*
 *  factory.cpp
 *  matrix
 *
 *  Created by Justin Turney on 4/8/08.
 *  Copyright 2008 __MyCompanyName__. All rights reserved.
 *
 */

#include "factory.h"
#include "sobasis.h"
#include <libparallel/parallel.h>
#include "libciomr/libciomr.h"

using namespace boost;
using namespace psi;

MatrixFactory::MatrixFactory()
{
    nirrep_ = 0;
    rowspi_ = NULL;
    colspi_ = NULL;
}

MatrixFactory::MatrixFactory(const MatrixFactory& copy)
{
    nirrep_ = copy.nirrep_;
    rowspi_ = new int[nirrep_];
    colspi_ = new int[nirrep_];

    memcpy(rowspi_, copy.rowspi_, sizeof(int) * nirrep_);
    memcpy(colspi_, copy.colspi_, sizeof(int) * nirrep_);
}

MatrixFactory::~MatrixFactory()
{
    if (rowspi_)
        Chkpt::free(rowspi_);
    if (colspi_)
        Chkpt::free(colspi_);
}

bool MatrixFactory::init_with_chkpt(boost::shared_ptr<PSIO> psio)
{
    boost::shared_ptr<Chkpt> chkpt(new Chkpt(psio.get(), PSIO_OPEN_OLD));
    bool result = init_with_chkpt(chkpt);
    return result;
}

bool MatrixFactory::init_with_chkpt(boost::shared_ptr<Chkpt> chkpt)
{
    nirrep_ = chkpt->rd_nirreps();
    rowspi_  = chkpt->rd_sopi();
    colspi_  = chkpt->rd_sopi();
    nso_     = chkpt->rd_nso();

    return true;
}

bool MatrixFactory::init_with(int nirreps, int *rowspi, int *colspi)
{
    nirrep_ = nirreps;
    rowspi_ = new int[nirrep_];
    colspi_ = new int[nirrep_];

    nso_ = 0;
    for (int i=0; i<nirrep_; ++i) {
        rowspi_[i] = rowspi[i];
        colspi_[i] = colspi[i];
        nso_ += rowspi_[i];
    }

    return true;
}

bool MatrixFactory::init_with(const Dimension& rows, const Dimension& cols)
{
    nirrep_ = rows.n();

    if (rows.n() != cols.n())
        throw PSIEXCEPTION("MatrixFactory can only handle same symmetry for rows and cols.");

    rowspi_ = new int[rows.n()];
    colspi_ = new int[cols.n()];

    nso_ = 0;
    for (int i=0; i<nirrep_; ++i) {
        rowspi_[i] = rows[i];
        colspi_[i] = cols[i];
        nso_ += rowspi_[i];
    }

    return true;
}

bool MatrixFactory::init_with(const boost::shared_ptr<SOBasisSet>& sobasis)
{
    return init_with(sobasis->dimension(), sobasis->dimension());
}
